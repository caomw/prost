#ifndef PROX_SEPARABLE_SUM_HPP_
#define PROX_SEPARABLE_SUM_HPP_

#include "prox.hpp"

using namespace thrust;
using namespace std;

/**
 * @brief Virtual base class for all proximal operators. Implements prox
 *        for sum of separable functions:
 *
 *        sum_{i=index_}^{index_+count_} f_i(x_i),
 *
 *        where the f_i and x_i are dim_ dimensional.
 *
 *        interleaved_ describes the ordering of the elements if dim_ > 1.
 *        If it is set to true, then successive elements in x correspond
 *        to one of count_ many dim_-dimensional vectors.
 *        If interleaved_ is set of false, then there are dim_ contigiuous
 *        chunks of count_ many elements.
 *
 */
template<typename T>
class ProxSeparableSum : public Prox<T> {
public:
  ProxSeparableSum(size_t index, size_t count, size_t dim, bool interleaved, bool diagsteps) : Prox(index, count*dim, diagsteps),
    count_(count),
    dim_(dim),
    interleaved_(interleaved) {}

  
  virtual ~ProxSeparableSum() {}

  /**
   * @brief Initializes the prox Operator, copies data to the GPU.
   *
   */
  virtual bool Init() { return true; }

  /**
   * @brief Cleans up GPU data.
   *
   */
  virtual void Release() {}

  // set/get methods
  virtual size_t gpu_mem_amount() = 0;
  size_t dim() const { return dim_; }
  size_t count() const { return count_; }
  bool interleaved() const { return interleaved_; }

protected:
  /**
   * @brief Evaluates the prox operator on the GPU, local meaning that
   *        d_arg, d_res and d_tau point to the place in memory where the
   *        prox begins.
   *
   * @param Proximal operator argument.
   * @param Result of prox.
   * @param Scalar step size.
   * @param Diagonal step sizes.
   * @param Perform the prox with inverted step sizes?
   *
   */
  virtual void EvalLocal(device_vector<T> d_arg,
                         device_vector<T> d_res,
                         device_vector<T> d_tau,
                         T tau,
                         bool invert_tau);
  
  size_t count_; 
  size_t dim_;
  bool interleaved_; // ordering of elements if dim > 1
};

#endif
