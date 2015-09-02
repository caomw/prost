#include "solver_backend_pdhg.hpp"

#include <cuComplex.h> // TODO: what was this needed for ...?
#include <iostream>
#include <sstream>

#include "util/cuwrap.hpp"

__global__
void ComputeProxArgPrimalPDHG(
    real *d_prox_arg,
    real *d_x,
    real tau,
    real *d_right,
    real *d_kty,
    int n) {
  
  int idx = threadIdx.x + blockIdx.x * blockDim.x;

  if(idx >= n)
    return;

  d_prox_arg[idx] = d_x[idx] - tau * d_right[idx] * d_kty[idx];
}

__global__
void ComputeProxArgDualPDHG(
    real *d_prox_arg,
    real *d_y,
    real sigma,
    real theta,
    real *d_left,
    real *d_kx,
    real *d_kx_prev,
    int m) {
  
  int idx = threadIdx.x + blockIdx.x * blockDim.x;

  if(idx >= m)
    return;

  d_prox_arg[idx] = d_y[idx] + sigma * d_left[idx] *
      ((1 + theta) * d_kx[idx] - theta * d_kx_prev[idx]);
}

__global__
void ComputePrimalResidualPDHG(
    real *d_res_primal,
    real *d_x,
    real *d_x_prev,
    real *d_kty,
    real *d_kty_prev,
    real tau,
    real *d_right,
    int n)
{
  int idx = threadIdx.x + blockIdx.x * blockDim.x;

  if(idx >= n)
    return;

  d_res_primal[idx] =
      ((d_x_prev[idx] - d_x[idx]) / (tau * d_right[idx])) -
      (d_kty_prev[idx] - d_kty[idx]);
}

__global__
void ComputeDualResidualPDHG(
    real *d_res_dual,
    real *d_y,
    real *d_y_prev,
    real *d_kx,
    real *d_kx_prev,
    real sigma,
    real *d_left,
    real theta,
    int m)
{
  int idx = threadIdx.x + blockIdx.x * blockDim.x;

  if(idx >= m)
    return;

  // TODO: derive residual for theta!=1?
  d_res_dual[idx] =
      ((d_y_prev[idx] - d_y[idx]) / (sigma * d_left[idx])) -
      (d_kx_prev[idx] - d_kx[idx]);
}

void SolverBackendPDHG::PerformIteration() {
  int n = problem_.mat->ncols();
  int m = problem_.mat->nrows();
  
  dim3 block(kBlockSizeCUDA, 1, 1);
  dim3 grid_n((n + block.x - 1) / block.x, 1, 1);
  dim3 grid_m((m + block.x - 1) / block.x, 1, 1);

  // gradient descent step
  ComputeProxArgPrimalPDHG<<<grid_n, block>>>(
      d_prox_arg_,
      d_x_,
      tau_,
      problem_.precond->right(),
      d_kty_,
      n);
  cudaDeviceSynchronize();

  // remember previous primal iterate
  std::swap(d_x_, d_x_prev_);

  // apply prox_g
  for(int j = 0; j < problem_.prox_g.size(); ++j)
    problem_.prox_g[j]->Evaluate(
        d_prox_arg_,
        d_x_,
        tau_,
        problem_.precond->right());

  // compute Kx^{k+1} and remember Kx^k
  std::swap(d_kx_, d_kx_prev_);
  problem_.mat->MultVec(d_x_, d_kx_, false, 1, 0);

  // gradient ascent step
  ComputeProxArgDualPDHG<<<grid_m, block>>>
      (d_prox_arg_,
       d_y_,
       sigma_,
       theta_,
       problem_.precond->left(),
       d_kx_,
       d_kx_prev_,
       m);
  cudaDeviceSynchronize();

  // apply prox_hc
  std::swap(d_y_, d_y_prev_);
  for(int j = 0; j < problem_.prox_hc.size(); ++j)
    problem_.prox_hc[j]->Evaluate(
        d_prox_arg_,
        d_y_,
        sigma_,
        problem_.precond->left());

  // compute K^T y^{k+1} and remember Ky^k
  std::swap(d_kty_, d_kty_prev_);
  problem_.mat->MultVec(d_y_, d_kty_, true, 1, 0);
  
  // compute residuals
  ComputePrimalResidualPDHG<<<grid_n, block>>>(
      d_res_primal_,
      d_x_,
      d_x_prev_,
      d_kty_,
      d_kty_prev_,
      tau_,
      problem_.precond->right(),
      n);

  ComputeDualResidualPDHG<<<grid_m, block>>>(
      d_res_dual_,
      d_y_,
      d_y_prev_,
      d_kx_,
      d_kx_prev_,
      sigma_,
      problem_.precond->left(),
      theta_,
      m);
  
  cudaDeviceSynchronize();

  cuwrap::asum<real>(cublas_handle_, d_res_primal_, n, &res_primal_);
  cuwrap::asum<real>(cublas_handle_, d_res_dual_, m, &res_dual_);

  //std::cout << res_primal << "," << res_dual << std::endl;
  
  // adapt step-sizes according to chosen algorithm
  switch(opts_.pdhg) {
    case kPDHGAlg1: // fixed step sizes, do nothing.
      break;

    case kPDHGAlg2: // adapt based on strong convexity constant gamma
      // TODO: implement me!
      break;

    case kPDHGAdapt: { // adapt based on residuals
      // TODO: implement me!
    } break;
  }
}

bool SolverBackendPDHG::Initialize() {
  int m = problem_.mat->nrows();
  int n = problem_.mat->ncols();
  int l = std::max(m, n);

  cudaMalloc((void **)&d_x_, n * sizeof(real));
  cudaMalloc((void **)&d_x_prev_, n * sizeof(real));
  cudaMalloc((void **)&d_kty_, n * sizeof(real));
  cudaMalloc((void **)&d_kty_prev_, n * sizeof(real));
  cudaMalloc((void **)&d_res_primal_, n * sizeof(real));
  cudaMalloc((void **)&d_y_, m * sizeof(real));
  cudaMalloc((void **)&d_y_prev_, m * sizeof(real));
  cudaMalloc((void **)&d_kx_, m * sizeof(real));
  cudaMalloc((void **)&d_kx_prev_, m * sizeof(real));
  cudaMalloc((void **)&d_res_dual_, m * sizeof(real));
  cudaMalloc((void **)&d_prox_arg_, l * sizeof(real));  

  tau_ = sigma_ = 1;
  theta_ = 1;

  // TODO: add possibility for non-zero initializations
  cudaMemset(d_x_, 0, n * sizeof(real));
  cudaMemset(d_x_prev_, 0, n * sizeof(real));
  cudaMemset(d_kty_, 0, n * sizeof(real));
  cudaMemset(d_kty_prev_, 0, n * sizeof(real));
  cudaMemset(d_res_primal_, 0, n * sizeof(real));
  cudaMemset(d_y_, 0, m * sizeof(real));
  cudaMemset(d_y_prev_, 0, m * sizeof(real));
  cudaMemset(d_res_dual_, 0, m * sizeof(real));
  cudaMemset(d_kx_, 0, m * sizeof(real));
  cudaMemset(d_kx_prev_, 0, m * sizeof(real));
  cudaMemset(d_prox_arg_, 0, l * sizeof(real));

  cublasCreate(&cublas_handle_);
  
  return true;
}

void SolverBackendPDHG::Release() {
  cublasDestroy(cublas_handle_);

  cudaFree(d_x_);
  cudaFree(d_y_);
  cudaFree(d_x_prev_);
  cudaFree(d_y_prev_);
  cudaFree(d_prox_arg_);
  cudaFree(d_kx_);
  cudaFree(d_kty_);
  cudaFree(d_kx_prev_);
  cudaFree(d_kty_prev_);
  cudaFree(d_res_primal_);
  cudaFree(d_res_dual_);
}

void SolverBackendPDHG::iterates(real *primal, real *dual) {
  cudaMemcpy(primal, d_x_, sizeof(real) * problem_.mat->ncols(), cudaMemcpyDeviceToHost);
  cudaMemcpy(dual, d_y_, sizeof(real) * problem_.mat->nrows(), cudaMemcpyDeviceToHost);
}

bool SolverBackendPDHG::converged() {
  return false; // TODO: implement stopping criteria based on residual
}

std::string SolverBackendPDHG::status() {
  std::stringstream ss;

  return ss.str();
}

int SolverBackendPDHG::gpu_mem_amount() {
  int m = problem_.mat->nrows();
  int n = problem_.mat->ncols();

  return (5 * (n + m) + std::max(n, m)) * sizeof(real);
}