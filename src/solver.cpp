#include "solver.hpp"

#include <iostream>
#include <sstream>
#include "solver_backend.hpp"
#include "solver_backend_pdhg.hpp"
#include "util/util.hpp"

Solver::Solver()
    : backend_(NULL), h_primal_(NULL), h_dual_(NULL) { 
}

Solver::~Solver() {
}

void Solver::SetMatrix(SparseMatrix<real>* mat) {
  problem_.mat = mat;
  problem_.nrows = mat->nrows();
  problem_.ncols = mat->ncols();
}

void Solver::SetProx_g(const std::vector<Prox*>& prox) {
  problem_.prox_g = prox;
}

void Solver::SetProx_hc(const std::vector<Prox*>& prox) {
  problem_.prox_hc = prox;
}

void Solver::SetOptions(const SolverOptions& opts) {
  opts_ = opts;
}

void Solver::SetCallback(SolverCallbackPtr cb) {
  callback_ = cb;
}

bool Solver::Initialize() {
  h_primal_ = new real[problem_.ncols];
  h_dual_ = new real[problem_.nrows];

  // create preconditioners
  problem_.precond = new Preconditioner(problem_.mat);
  switch(opts_.precond)
  {
    case kPrecondScalar:
      problem_.precond->ComputeScalar();
      break;

    case kPrecondAlpha:
      return false; // not implemented yet

    case kPrecondEquil:
      return false; // not implemented yet
  }

  // create backend
  switch(opts_.backend)
  {
    case kBackendPDHG:
      backend_ = new SolverBackendPDHG(problem_, opts_);
      break;

    default:
      return false;
  }


  if(!backend_->Initialize())
    return false;

  return true;
}

void Solver::gpu_mem_amount(size_t& gpu_mem_required, size_t& gpu_mem_avail) {
  // calculate memory requirements
  gpu_mem_required = 0;
  gpu_mem_avail = 0;
  size_t gpu_mem_free;
  
  for(int i = 0; i < problem_.prox_g.size(); ++i)
    gpu_mem_required += problem_.prox_g[i]->gpu_mem_amount();

  for(int i = 0; i < problem_.prox_hc.size(); ++i)
    gpu_mem_required += problem_.prox_hc[i]->gpu_mem_amount();

  gpu_mem_required += backend_->gpu_mem_amount();
  gpu_mem_required += problem_.mat->gpu_mem_amount();
  gpu_mem_required += problem_.precond->gpu_mem_amount();

  cudaMemGetInfo(&gpu_mem_free, &gpu_mem_avail);
}

void Solver::Solve() {
  // iterations to display
  std::list<double> cb_iters =
      linspace(0, opts_.max_iters - 1, opts_.cb_iters);
  
  for(int i = 0; i < opts_.max_iters; i++) {    
    backend_->PerformIteration();
    bool is_converged = backend_->converged();

    // check if we should run the callback this iteration
    if(i >= cb_iters.front()) {
      backend_->iterates(h_primal_, h_dual_);
      callback_(i + 1, h_primal_, h_dual_, false);
      cb_iters.pop_front();
    }

    if(is_converged)
      break;
  }
}

void Solver::Release() {
  backend_->Release();

  for(int i = 0; i < problem_.prox_g.size(); i++)
    delete problem_.prox_g[i];

  for(int i = 0; i < problem_.prox_hc.size(); i++)
    delete problem_.prox_hc[i];
  
  delete [] h_primal_;
  delete [] h_dual_;
  delete problem_.precond;
  delete problem_.mat;
}

std::string SolverOptions::get_string() const {
  std::stringstream ss;

  ss << "Specified solver options:" << std::endl;
  ss << " - backend:";
  if(backend == kBackendPDHG) {
    ss << " PDHG,";

    switch(pdhg) {
      case kPDHGAlg1:
        ss << " with constant steps (Alg. 1)." << std::endl;
        break;

      case kPDHGAlg2:
        ss << " accelerated version for strongly convex problems (Alg. 2). gamma = " << gamma << std::endl;
        break;

      case kPDHGAdapt:
        ss << " adaptive step sizes. (alpha0 = " << alpha0;
        ss << ", nu = " << nu;
        ss << ", delta = " << delta;
        ss << ", s = " << s << ")." << std::endl;
        break;
    }
  }
  ss << " - max_iters: " << max_iters << std::endl;
  ss << " - cb_iters: " << cb_iters << std::endl;
  ss << " - tolerance: " << tolerance << std::endl;
  ss << " - verbose: " << verbose << std::endl;
  ss << " - preconditioning: ";

  switch(precond) {
    case kPrecondScalar:
      ss << "scalar." << std::endl;
      break;
    case kPrecondAlpha:
      ss << "diagonal (alpha = " << precond_alpha << ")." << std::endl;
      break;
    case kPrecondEquil:
      ss << "matrix equilibration." << std::endl;
      break;
  }
  
  return ss.str();
}