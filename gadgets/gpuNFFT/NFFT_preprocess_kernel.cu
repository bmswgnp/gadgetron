//
// NFFT_H preprocessing kernels
//

// convert input trajectory in [-1/2;1/2] to [0;matrix_size_os+matrix_size_wrap]
template<class REALd> struct trajectory_scale
{
  const REALd matrix, bias;
  
  trajectory_scale(REALd m, REALd b) : matrix(m), bias(b) {}
  
  __host__ __device__
  REALd operator()(const REALd &in) const { 
    return (in*matrix)+bias;
  }
};

template <class REALd, class REAL>
struct compute_num_cells_per_sample
{
  __host__ __device__
  compute_num_cells_per_sample(unsigned int _d, REAL _half_W) : d(_d), half_W(_half_W) {}
  
  __host__ __device__
  unsigned int operator()(REALd p) const
  {
    unsigned int num_cells = 1;
    for( unsigned int dim=0; dim<d; dim++ ){
      unsigned int upper_limit = (unsigned int)floor((((float*)&p)[dim])+half_W);
      unsigned int lower_limit = (unsigned int)ceil((((float*)&p)[dim])-half_W);
      num_cells *= (upper_limit-lower_limit+1);
    }
    return num_cells;
  }
  
  unsigned int d;
  REAL half_W;
};

// TODO: can we avoid overloading here?
template <class REALd, class REAL> __inline__ __device__ void
output_pairs( unsigned int sample_idx, REALd p, uint2 matrix_size_os, uint2 matrix_size_wrap, REAL half_W, unsigned int *write_offsets, unsigned int *tuples_first, unsigned int *tuples_last )
{
  unsigned int lower_limit_x = (unsigned int)ceil(p.x-half_W);
  unsigned int lower_limit_y = (unsigned int)ceil(p.y-half_W);
  unsigned int upper_limit_x = (unsigned int)floor(p.x+half_W);
  unsigned int upper_limit_y = (unsigned int)floor(p.y+half_W);

  unsigned int pair_idx = 0;
  unsigned int write_offset = (sample_idx==0) ? 0 : write_offsets[sample_idx-1];
  for( unsigned int y=lower_limit_y; y<=upper_limit_y; y++ ){
    for( unsigned int x=lower_limit_x; x<=upper_limit_x; x++ ){
      tuples_first[write_offset+pair_idx] = co_to_idx(make_uint2(x,y), matrix_size_os+matrix_size_wrap);
      tuples_last[write_offset+pair_idx] = sample_idx;
      pair_idx++;
    }
  }
}

template <class REALd, class REAL> __inline__ __device__ void
output_pairs( unsigned int sample_idx, REALd p, uint3 matrix_size_os, uint3 matrix_size_wrap, REAL half_W, unsigned int *write_offsets, unsigned int *tuples_first, unsigned int *tuples_last )
{
  unsigned int lower_limit_x = (unsigned int)ceil(p.x-half_W);
  unsigned int lower_limit_y = (unsigned int)ceil(p.y-half_W);
  unsigned int lower_limit_z = (unsigned int)ceil(p.z-half_W);
  unsigned int upper_limit_x = (unsigned int)floor(p.x+half_W);
  unsigned int upper_limit_y = (unsigned int)floor(p.y+half_W);
  unsigned int upper_limit_z = (unsigned int)floor(p.z+half_W);

  unsigned int pair_idx = 0;
  unsigned int write_offset = (sample_idx==0) ? 0 : write_offsets[sample_idx-1];
  for( unsigned int z=lower_limit_z; z<=upper_limit_z; z++ ){
    for( unsigned int y=lower_limit_y; y<=upper_limit_y; y++ ){
      for( unsigned int x=lower_limit_x; x<=upper_limit_x; x++ ){
	tuples_first[write_offset+pair_idx] = co_to_idx(make_uint3(x,y,z), matrix_size_os+matrix_size_wrap);
	tuples_last[write_offset+pair_idx] = sample_idx;
	pair_idx++;
      }
    }
  }
}

template <class REALd, class REAL> __inline__ __device__ void
output_pairs( unsigned int sample_idx, REALd p, uint4 matrix_size_os, uint4 matrix_size_wrap, REAL half_W, unsigned int *write_offsets, unsigned int *tuples_first, unsigned int *tuples_last )
{
  unsigned int lower_limit_x = (unsigned int)ceil(p.x-half_W);
  unsigned int lower_limit_y = (unsigned int)ceil(p.y-half_W);
  unsigned int lower_limit_z = (unsigned int)ceil(p.z-half_W);
  unsigned int lower_limit_w = (unsigned int)ceil(p.w-half_W);
  unsigned int upper_limit_x = (unsigned int)floor(p.x+half_W);
  unsigned int upper_limit_y = (unsigned int)floor(p.y+half_W);
  unsigned int upper_limit_z = (unsigned int)floor(p.z+half_W);
  unsigned int upper_limit_w = (unsigned int)floor(p.w+half_W);

  unsigned int pair_idx = 0;
  unsigned int write_offset = (sample_idx==0) ? 0 : write_offsets[sample_idx-1];
  for( unsigned int w=lower_limit_w; w<=upper_limit_w; w++ ){
    for( unsigned int z=lower_limit_z; z<=upper_limit_z; z++ ){
      for( unsigned int y=lower_limit_y; y<=upper_limit_y; y++ ){
	for( unsigned int x=lower_limit_x; x<=upper_limit_x; x++ ){
	  tuples_first[write_offset+pair_idx] = co_to_idx(make_uint4(x,y,z,w), matrix_size_os+matrix_size_wrap);
	  tuples_last[write_offset+pair_idx] = sample_idx;
	  pair_idx++;
	}
      }
    }
  }
}

template <class UINTd, class REALd, class REAL> __global__ void
write_pairs_kernel( UINTd matrix_size_os, UINTd matrix_size_wrap, unsigned int num_samples, REAL half_W, REALd *traj_positions, unsigned int *write_offsets, unsigned int *tuples_first, unsigned int *tuples_last )
{
  // Get sample idx
  unsigned int sample_idx = blockIdx.x*blockDim.x + threadIdx.x;

  if( sample_idx<num_samples ){

    REALd p = traj_positions[sample_idx];
    output_pairs<REALd, REAL>( sample_idx, p, matrix_size_os, matrix_size_wrap, half_W, write_offsets, tuples_first, tuples_last );
  }
};

template <class UINTd, class REALd, class REAL> void 
write_pairs( UINTd matrix_size_os, UINTd matrix_size_wrap, unsigned int num_samples, REAL W, REALd *traj_positions, unsigned int *write_offsets, unsigned int *tuples_first, unsigned int *tuples_last )
{  
  dim3 blockDim(512);
  dim3 gridDim((int)ceil((double)num_samples/(double)blockDim.x));

  REAL half_W = half(W);
  write_pairs_kernel<UINTd, REALd><<< gridDim, blockDim >>>
    ( matrix_size_os, matrix_size_wrap, num_samples, half_W, traj_positions, write_offsets, tuples_first, tuples_last );

 CHECK_FOR_CUDA_ERROR();
}