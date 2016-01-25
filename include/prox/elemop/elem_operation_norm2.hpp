#ifndef ELEM_OPERATION_NORM2_HPP_
#define ELEM_OPERATION_NORM2_HPP_

#include "elem_operation.hpp"
#include "function_1d.hpp"
/**
 * @brief Provides proximal operator for sum of 2-norms, with a nonlinear
 *        function ProxFunction1D applied to the norm.
 *
 *
 *
 */
template<typename T, size_t DIM, class FUN_1D>
struct ElemOperationNorm2 : public ElemOperation<DIM> {

 struct Coefficients : public Coefficients1D<T> {};
   __device__ ElemOperationNorm2() {} 
 
 __device__ ElemOperationNorm2(Coefficients* coeffs) : coeffs_(coeffs) {} 
 
 
 inline __device__ void operator()(Vector<T, ElemOperationNorm2<T, DIM, FUN_1D>>& arg, Vector<T, ElemOperationNorm2<T, DIM, FUN_1D>>& res, Vector<T,ElemOperationNorm2<T, DIM, FUN_1D>>& tau_diag, T tau_scal, bool invert_tau, SharedMem<ElemOperationNorm2<T, DIM, FUN_1D>>& shared_mem) {
    // compute dim-dimensional 2-norm at each point
    T norm = 0;

    for(size_t i = 0; i < DIM; i++) {
      const T val = arg[i];
      norm += val * val;
    }
    
    //TODO check coeffs_.val[i] == NULL
    
    if(norm > 0) {
      norm = sqrt(norm);

      // compute step-size
      const T tau = invert_tau ? (1. / (tau_scal * tau_diag[0])) : (tau_scal * tau_diag[0]);

      // compute scaled prox argument and step 
      const T prox_arg = ((coeffs_->a * (norm - coeffs_->d * tau)) /
                     (1. + tau * coeffs_->e)) - coeffs_->b;
    
      const T step = (coeffs_->c * coeffs_->a * coeffs_->a * tau) /
                     (1. + tau * coeffs_->e);
      
      // compute prox
      FUN_1D fun;
      const T prox_result = (fun(prox_arg, step, coeffs_->alpha, coeffs_->beta) +
                             coeffs_->b) / coeffs_->a;

      // combine together for result
      for(size_t i = 0; i < DIM; i++) {
        res[i] = prox_result * arg[i] / norm;
      }
    } else { // in that case, the result is zero. 
      for(size_t i = 0; i < DIM; i++) {
        res[i] = 0;
      }
    }
 }
   
private:
  Coefficients* coeffs_;
};
#endif
