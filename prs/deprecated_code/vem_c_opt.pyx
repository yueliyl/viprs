# cython: linetrace=False
# cython: profile=False
# cython: binding=False
# cython: boundscheck=False
# cython: wraparound=False
# cython: initializedcheck=False
# cython: nonecheck=False
# cython: language_level=3
# cython: infer_types=True
import numpy as np
from libc.math cimport log
from .PRSModel cimport PRSModel
from .c_utils cimport dot, sigmoid, elementwise_add_mult, clip


cdef class vem_prs_opt(PRSModel):

    cdef public:
        double pi, sigma_beta, sigma_epsilon  # Global parameters
        bint scale_prior
        dict var_mu_beta, var_sigma_beta, var_gamma  # Variational parameters
        dict beta_hat, ld, ld_bounds  # Inputs to the algorithm
        dict q, history, fix_params  # Helpers

    def __init__(self, gdl, scale_prior=False, fix_params=None, load_ld=True):
        """
        :param scale_prior: If set to true, scale the prior over the parameters
                following the Carbonetto & Stephens (2012) model).
        :param gdl: An instance of GWAS data loader
        """

        super().__init__(gdl)

        self.var_mu_beta = {}
        self.var_sigma_beta = {}
        self.var_gamma = {}
        self.q = {}

        if load_ld:
            self.gdl.load_ld()

        self.ld = self.gdl.get_ld_matrices()
        self.ld_bounds = self.gdl.get_ld_boundaries()
        self.beta_hat = self.gdl.beta_hats

        self.scale_prior = scale_prior
        self.fix_params = fix_params or {}

        self.history = {}

        self.initialize()

    cpdef initialize(self):
        self.beta_hat = self.gdl.beta_hats
        self.initialize_variational_params()
        self.initialize_theta()
        self.init_history()

    cpdef init_history(self):

        self.history = {
            'ELBO': [],
            'pi': [],
            'sigma_beta': [],
            'sigma_epsilon': [],
            'heritability': []
        }

    cpdef initialize_theta(self):

        if 'sigma_beta' not in self.fix_params:
            self.sigma_beta = np.random.uniform(low=1e-6, high=.1)
        else:
            self.sigma_beta = self.fix_params['sigma_beta']

        if 'sigma_epsilon' not in self.fix_params:
            self.sigma_epsilon = np.random.uniform(low=.5, high=1.)
        else:
            self.sigma_epsilon = self.fix_params['sigma_epsilon']

        if 'pi' not in self.fix_params:
            self.pi = np.random.uniform(low=1. / self.M, high=.5)
        else:
            self.pi = self.fix_params['pi']

    cpdef initialize_variational_params(self):

        self.var_mu_beta = {}
        self.var_sigma_beta = {}
        self.var_gamma = {}

        for c, c_size in self.shapes.items():

            self.q[c] = np.zeros(shape=c_size)
            self.var_gamma[c] = np.random.uniform(size=c_size)
            self.var_mu_beta[c] = np.random.normal(scale=1./np.sqrt(self.M), size=c_size)
            self.var_sigma_beta[c] = np.repeat(1./self.M, c_size)

    cpdef e_step(self):
        """
        In the E-step, we update the variational parameters
        for each SNP.
        :return:
        """

        cdef:
            unsigned int i, start, end
            double u_j
            double[::1] var_prod, var_mu_beta, var_sigma_beta, var_gamma, beta_hat, q, Di
            long[:, ::1] ld_bound

        # The prior variance parameter (can be defined in two ways):
        cdef double prior_var = self.sigma_epsilon*self.sigma_beta if self.scale_prior else self.sigma_beta

        # The denominator for the mu_beta updates:
        cdef double denom = (1. + self.sigma_epsilon / (self.N * prior_var))

        # The log(pi) for the gamma updates
        cdef double log_pi = log(self.pi / (1. - self.pi))

        for c, c_size in self.shapes.items():

            # Updates for sigma_beta variational parameters:
            self.var_sigma_beta[c] = np.repeat(
                self.sigma_epsilon / (self.N + self.sigma_epsilon / prior_var),
                c_size
            )

            beta_hat = self.beta_hat[c].values
            var_mu_beta = self.var_mu_beta[c]
            var_sigma_beta = self.var_sigma_beta[c]
            var_gamma = self.var_gamma[c]
            ld_bound = self.ld_bounds[c]
            q = np.zeros(shape=c_size)

            var_prod = np.multiply(var_gamma, var_mu_beta)

            for i, Di in enumerate(self.ld[c]):


                start, end = ld_bound[0, i], ld_bound[1, i]
                i_idx = i - start

                # Compute the variational estimate of mu beta:
                var_mu_beta[i] = (beta_hat[i] - dot(Di, var_prod[start: end]) +
                                  Di[i_idx]*var_prod[i]) / denom

                # Compute the variational estimate of gamma
                u_i = (log_pi + .5*log(var_sigma_beta[i] / prior_var) +
                       (.5/var_sigma_beta[i])*var_mu_beta[i]*var_mu_beta[i])
                var_gamma[i] = clip(sigmoid(u_i), 1e-6, 1. - 1e-6)

                # Update the expectation of beta:
                var_prod[i] = var_gamma[i]*var_mu_beta[i]

                if i_idx > 0:
                    # Update the q factor for snp i by adding the contribution of previous SNPs.
                    q[i] = dot(Di[:i_idx], var_prod[start: i])
                    # Update the q factors for all previously updated SNPs that are in LD with SNP i
                    q[start: i] = elementwise_add_mult(q[start: i], Di[:i_idx], var_prod[i])

            self.q[c] = np.array(q)
            self.var_gamma[c] = np.array(var_gamma)
            self.var_mu_beta[c] = np.array(var_mu_beta)

    cpdef m_step(self):
        """
        In the M-step, we update the global parameters of
        the model.
        :return:
        """

        # Update pi:

        var_gamma_sum = np.sum([
            np.sum(self.var_gamma[c])
            for c in self.var_gamma
        ])

        if 'pi' not in self.fix_params:
            self.pi = var_gamma_sum / self.M
            self.pi = clip(self.pi, 1./self.M, 1.)

        self.history['pi'].append(self.pi)

        if 'sigma_beta' not in self.fix_params:
            # Update sigma_beta:
            self.sigma_beta = np.sum([
                np.dot(self.var_gamma[c],
                       self.var_mu_beta[c] ** 2 + self.var_sigma_beta[c])
                for c in self.var_mu_beta]) / var_gamma_sum

            if self.scale_prior:
                self.sigma_beta /= self.sigma_epsilon

            self.sigma_beta = clip(self.sigma_beta, 1e-12, 1e12)

        self.history['sigma_beta'].append(self.sigma_beta)

        if 'sigma_epsilon' not in self.fix_params:

            # Update sigma_epsilon
            scale_prior_adj = (1. + 1. / (self.N * self.sigma_beta)) if self.scale_prior else 1.

            sig_eps = 0.

            for c, c_size in self.shapes.items():
                beta_hat = self.beta_hat[c].values
                var_gamma = self.var_gamma[c]
                var_mu_beta = self.var_mu_beta[c]
                var_sigma_beta = self.var_sigma_beta[c]
                var_prod = np.multiply(var_gamma, var_mu_beta)
                q = self.q[c]

                sig_eps += (
                        - 2. * np.dot(var_prod, beta_hat) +
                        scale_prior_adj * np.dot(var_gamma, var_mu_beta * var_mu_beta + var_sigma_beta) +
                        np.dot(var_prod, q)
                )

            final_sig_e = 1. + sig_eps

            if self.scale_prior:
                final_sig_e *= (self.N / (self.N + var_gamma_sum))

            self.sigma_epsilon = clip(final_sig_e, 1e-12, 1e12)

        self.history['sigma_epsilon'].append(self.sigma_epsilon)

    cpdef objective(self):

        loglik = 0.  # log of joint density
        ent = 0.  # entropy

        cdef double prior_var = self.sigma_epsilon * self.sigma_beta if self.scale_prior else self.sigma_beta

        # Add the fixed quantities:

        loglik -= .5 * self.N * (np.log(2 * np.pi * self.sigma_epsilon) + 1. / self.sigma_epsilon)
        loglik -= .5 * self.M * np.log(2. * np.pi * prior_var)
        loglik += self.M * np.log(1. - self.pi)

        ent += .5 * self.M * np.log(2. * np.pi * np.e * prior_var)

        for c in self.var_mu_beta:
            beta_hat = self.beta_hat[c]
            gamma_mu = self.var_gamma[c] * self.var_mu_beta[c]
            gamma_mu_sig = self.var_gamma[c] * (self.var_mu_beta[c] ** 2 + self.var_sigma_beta[c])

            loglik += (-.5 * self.N / self.sigma_epsilon) * (
                    - 2. * np.dot(gamma_mu, beta_hat)
                    + np.dot(gamma_mu, self.q[c])
                    + np.sum(gamma_mu_sig)
            )

            loglik += (-.5 / prior_var) * (
                    np.sum(gamma_mu_sig) +
                    prior_var * np.sum(1 - self.var_gamma[c])
            )

            loglik += np.log(self.pi / (1. - self.pi)) * np.sum(self.var_gamma[c])

            ent += .5 * np.dot(self.var_gamma[c], np.log(self.var_sigma_beta[c] / prior_var))

            ent -= np.dot(self.var_gamma[c], np.log(self.var_gamma[c] / (1. - self.var_gamma[c])))
            ent -= np.sum(np.log(1. - self.var_gamma[c]))

        elbo = loglik + ent

        self.history['ELBO'].append(elbo)
        #self.history['loglikelihood'].append(loglik)
        #self.history['entropy'].append(ent)

        return elbo

    cpdef get_proportion_causal(self):
        return self.pi

    cpdef get_heritability(self):

        sigma_g = np.sum([
            np.sum(self.var_gamma[c] * (self.var_mu_beta[c] ** 2 + self.var_sigma_beta[c])) +
            np.dot(self.q[c], self.var_gamma[c] * self.var_mu_beta[c])
            for c in self.var_gamma
        ])

        h2g = sigma_g / (sigma_g + self.sigma_epsilon)

        self.history['heritability'].append(h2g)

        return h2g

    cpdef fit(self, max_iter=500, continued=False, tol=1e-6, max_elbo_drops=10):

        if not continued:
            self.initialize()

        elbo_dropped_count = 0
        converged = False

        for i in range(1, max_iter + 1):

            self.e_step()
            self.m_step()
            self.objective()
            self.get_heritability()

            if i > 1:

                if self.history['ELBO'][i-1] < self.history['ELBO'][i-2]:
                    elbo_dropped_count += 1
                    print(f"Warning (Iteration {i}): ELBO dropped from {self.history['ELBO'][i-2]:.6f} "
                          f"to {self.history['ELBO'][i-1]:.6f}.")

                if np.abs(self.history['ELBO'][i-1] - self.history['ELBO'][i-2]) <= tol:
                    print(f"Converged at iteration {i} | ELBO: {self.history['ELBO'][i-1]:.6f}")
                    break
                elif elbo_dropped_count > max_elbo_drops:
                    print("The optimization is halted due to numerical instabilities!")
                    break

        if i == max_iter:
            print("Max iterations reached without convergence. "
                  "You may need to run the model for more iterations.")

        self.pip = self.var_gamma
        self.inf_beta = {c: self.var_gamma[c] * self.var_mu_beta[c]
                         for c, v in self.var_gamma.items()}

        return self