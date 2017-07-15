#include <vector>
#include <algorithm>
#include <iostream>
using namespace std;

#include "caffe/layers/cmp_conv_layer.hpp"

namespace caffe {


template <typename Dtype>
void CmpConvolutionLayer<Dtype>::Forward_gpu(const vector<Blob<Dtype>*>& bottom,
      const vector<Blob<Dtype>*>& top) {
  Dtype* muweight = this->blobs_[0]->mutable_cpu_data();
  int count = this->blobs_[0]->count();
  
  for (int i = 0; i < count; ++i)
    muweight[i] *= this->masks_[i] ;

  if(this->quantize_term_)
  {
    for (int i = 0; i < count; ++i)
    {   
       if (this->masks_[i])
         muweight[i] = this->centroids_[this->indices_[i]];
    }   
  }

  const Dtype* weight = this->blobs_[0]->gpu_data();
  for (int i = 0; i < bottom.size(); ++i) {
    const Dtype* bottom_data = bottom[i]->gpu_data();
    Dtype* top_data = top[i]->mutable_gpu_data();
    for (int n = 0; n < this->num_; ++n) {
      this->forward_gpu_gemm(bottom_data + n * this->bottom_dim_, weight,
          top_data + n * this->top_dim_);
      if (this->bias_term_) {
        const Dtype* bias = this->blobs_[1]->gpu_data();
        this->forward_gpu_bias(top_data + n * this->top_dim_, bias);
      }
    }
  }
}

template <typename Dtype>
void CmpConvolutionLayer<Dtype>::Backward_gpu(const vector<Blob<Dtype>*>& top,
      const vector<bool>& propagate_down, const vector<Blob<Dtype>*>& bottom) {
    //  LOG(INFO) << "conv backward"<<endl;
  const Dtype* weight = this->blobs_[0]->gpu_data();
  Dtype* weight_diff = this->blobs_[0]->mutable_gpu_diff();
  int count = this->blobs_[0]->count();
  for (int i = 0; i < top.size(); ++i) {
    const Dtype* top_diff = top[i]->gpu_diff();
    // Bias gradient, if necessary.
    if (this->bias_term_ && this->param_propagate_down_[1]) {
      Dtype* bias_diff = this->blobs_[1]->mutable_gpu_diff();
      for (int n = 0; n < this->num_; ++n) {
        this->backward_gpu_bias(bias_diff, top_diff + n * this->top_dim_);
      }
    }
    if (this->param_propagate_down_[0] || propagate_down[i]) {
      const Dtype* bottom_data = bottom[i]->gpu_data();
      Dtype* bottom_diff = bottom[i]->mutable_gpu_diff();
      for (int n = 0; n < this->num_; ++n) {
        // gradient w.r.t. weight. Note that we will accumulate diffs.
        if (this->param_propagate_down_[0]) {
          this->weight_gpu_gemm(bottom_data + n * this->bottom_dim_,
              top_diff + n * this->top_dim_, weight_diff);
        }

     	Dtype* weight_diff = this->blobs_[0]->mutable_cpu_diff();
        for (int j = 0; j < count; ++j)
          weight_diff[j] *= this->masks_[j];
        if(this->quantize_term_)
        {
          vector<Dtype> tmpDiff(this->class_num_);
          vector<int> freq(this->class_num_);
          for (int j = 0; j < count; ++j)
          {
            if (this->masks_[j])
            {
              tmpDiff[this->indices_[j]] += weight_diff[j];
              freq[this->indices_[j]]++;
            }
          }
          for (int j = 0; j < count; ++j)
          {
            if (this->masks_[j])
              weight_diff[j] = tmpDiff[this->indices_[j]] / freq[this->indices_[j]];
          }
        }


        // gradient w.r.t. bottom data, if necessary.
        if (propagate_down[i]) {
          this->backward_gpu_gemm(top_diff + n * this->top_dim_, weight,
              bottom_diff + n * this->bottom_dim_);
        }
      }
    }
  }
}

INSTANTIATE_LAYER_GPU_FUNCS(CmpConvolutionLayer);

}  // namespace caffe