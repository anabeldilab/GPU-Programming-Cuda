/*
 ============================================================================
 Proyecto GPU
 Realizado por: Anabel Díaz Labrador

 ============================================================================
 */


#include <iostream>

#include <cuda_runtime.h>

static void CheckCudaErrorAux (const char *, unsigned, const char *, cudaError_t);
#define CUDA_CHECK_RETURN(value) CheckCudaErrorAux(__FILE__,__LINE__, #value, value)

void show_vector(int*, int, int);

#define N (1048576)
#define M (8)
#define HILOSPORBLOQUE (512)


// Device kernel
__global__ void incHist(const int *A, int numElements, int *histogram, int numElementsHistograms) {
  int i = blockDim.x * blockIdx.x + threadIdx.x;
  
  if (i < numElements) {
    int increment = A[i] % M;
    atomicAdd(&histogram[M * blockIdx.x + increment], 1);
  }
}

// Device kernel
__global__ void reduccion_paralela(int *histogram, int numElements, int *result) {
  int i = blockDim.x * blockIdx.x + threadIdx.x;

  if (i < numElements) {
    for(unsigned int middle = numElements / 2; middle >= M; middle >>= 1) { // We reduce until there are 8 left to join. Last iteration middle = 4
      if (i < middle) {
        histogram[i] = histogram[i] + histogram[i + middle];
      }
      __syncthreads();
    }
  } 

  if (i >= 0 && i < M) {
    result[i] = histogram[i];
  }
}


// Host main
int main(void) {
  // Vector length to be used, and compute its size
  const int numElementsA = N;
  size_t sizeA = numElementsA * sizeof(int);

  // Allocate the host input vector A
  int *h_A = (int*)malloc(sizeA);

  // Verify that allocations succeeded
  if (h_A == NULL) {
      fprintf(stderr, "Failed to allocate host vectors!\n");
      exit(EXIT_FAILURE);
  }

  // Initialize the host input vector with [0, 1000000] random range
  time_t t;
  srand((unsigned) time(&t));
  for (int i = 0; i < numElementsA; i++) {
    h_A[i] = rand() % N;
  }
  printf("Vector element number: %d\n", numElementsA);
  //show_vector(h_A, 0, 10); Check that adds random numbers

  // Allocate the device input vector A
  int *d_A = NULL;
  CUDA_CHECK_RETURN(cudaMalloc((void**)&d_A, sizeA));

  // Copy the host input vector A in host memory to the device input vector in
  // device memory
  printf("Copy input data from the host memory to the CUDA device\n");
  CUDA_CHECK_RETURN(cudaMemcpy(d_A, h_A, sizeA, cudaMemcpyHostToDevice));

  // Calculate the number of blocks needed
  int threadsPerBlock = HILOSPORBLOQUE;
  int blocksPerGrid = (numElementsA + threadsPerBlock - 1) / threadsPerBlock;

  // Vector length to be used, and compute its size
  int numElementsHistograms = blocksPerGrid * M;
  size_t sizeHistograms = numElementsHistograms * sizeof(int);

  // Allocate the host input vector histogram
  int *h_histograms = (int*)malloc(sizeHistograms);
  if (h_histograms == NULL) {
      fprintf(stderr, "Failed to allocate host vectors!\n");
      exit(EXIT_FAILURE);
  }

  // Initialize the host input vector
  for (int i = 0; i < numElementsHistograms; i++) {
    h_histograms[i] = 0;
  }

  // Allocate the device input vector histogram
  int *d_histograms = NULL;
  CUDA_CHECK_RETURN(cudaMalloc((void**)&d_histograms, sizeHistograms));

  // Copy the host input vector histograms in host memory to the device input vector in
  // device memory
  printf("Copy input data from the host memory to the CUDA device\n");
  CUDA_CHECK_RETURN(cudaMemcpy(d_histograms, h_histograms, sizeHistograms, cudaMemcpyHostToDevice));

  // Launch the incHist CUDA Kernel
  printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);
  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);

  cudaEventRecord(start, 0);
  incHist<<<blocksPerGrid, threadsPerBlock>>>(d_A, numElementsA, d_histograms, numElementsHistograms);
  cudaEventRecord(stop, 0);
  cudaEventSynchronize(stop);
  CUDA_CHECK_RETURN(cudaGetLastError());

  float elapsedTime1;
  cudaEventElapsedTime(&elapsedTime1, start, stop);
  
  // Get back the histograms
  printf("Copy local histograms from the CUDA device to the host memory\n");
  CUDA_CHECK_RETURN(cudaMemcpy(h_histograms, d_histograms, sizeHistograms, cudaMemcpyDeviceToHost));

  // Vector check
  printf("\nFirst 8 elements of the vector of local histograms: ");
  show_vector(h_histograms, 0, M);
  int acc = 0;
  for (int i = 0; i < numElementsHistograms; i++) {
    acc += h_histograms[i];
  }
  printf("Histogram total increments: %d\nHistogram size: %d\n", acc, numElementsHistograms);

  // Vector length to be used, and compute its size
  int numElementsHistogram = M;
  size_t sizeHistogram = numElementsHistogram * sizeof(int);


  // Allocate the host input vector histograma
  int *h_histogram = (int*)malloc(sizeHistogram);
  if (h_histogram == NULL) {
      fprintf(stderr, "Failed to allocate host vectors!\n");
      exit(EXIT_FAILURE);
  }

  // Allocate the device input vector histogram
  int *d_histogram = NULL;
  CUDA_CHECK_RETURN(cudaMalloc((void**)&d_histogram, sizeHistogram));

  // Initialize the host input vector
  for (int i = 0; i < M; i++) {
    h_histogram[i] = 0;
  }

  // Copy the host input vector histogram in host memory to the device input vector in
  // device memory
  printf("Copy input data from the host memory to the CUDA device\n");
  CUDA_CHECK_RETURN(cudaMemcpy(d_histogram, h_histogram,  sizeHistogram, cudaMemcpyHostToDevice));

  // Launch the reduccion_paralela CUDA Kernel
  blocksPerGrid = (numElementsHistograms + threadsPerBlock - 1) / threadsPerBlock;
  printf("CUDA kernel launch with %d blocks of %d threads\n", blocksPerGrid, threadsPerBlock);
  cudaEventRecord(start, 0);
  reduccion_paralela<<<blocksPerGrid, threadsPerBlock>>>(d_histograms, numElementsHistograms, d_histogram);
  cudaEventRecord(stop, 0);
  cudaEventSynchronize(stop);
  CUDA_CHECK_RETURN(cudaGetLastError());

  float elapsedTime2;
  cudaEventElapsedTime(&elapsedTime2, start, stop);

  // Get back the histogram result
  printf("Copy histogram result from the CUDA device to the host memory\n");
  CUDA_CHECK_RETURN(cudaMemcpy(h_histogram, d_histogram, sizeHistogram, cudaMemcpyDeviceToHost));

  // Vector check
  show_vector(h_histogram, 0, M);
  acc = 0;
  for (int i = 0; i < M; i++) {
    acc += h_histogram[i];
  }
  printf("Histogram total data: %d\n", acc);

  // Free device global memory
  CUDA_CHECK_RETURN(cudaFree(d_A));
  CUDA_CHECK_RETURN(cudaFree(d_histograms));
  CUDA_CHECK_RETURN(cudaFree(d_histogram));

  // Free host memory
  free(h_A);
  free(h_histograms);
  free(h_histogram);

  printf("\nTiempo construyendo histogramas locales: %f milisegundos\n", elapsedTime1);
  printf("Tiempo juntando histogramas en uno final: %f milisegundos\n", elapsedTime2);
  printf("Tiempo total: %f milisegundos\n", elapsedTime1 + elapsedTime2);
  cudaEventDestroy(start);
  cudaEventDestroy(stop);

  printf("Done\n");
  return EXIT_SUCCESS;
}


// Check the return value of the CUDA runtime API call and exit the application if the call has failed.
static void CheckCudaErrorAux (const char *file, unsigned line, const char *statement, cudaError_t err) {

	if (err == cudaSuccess)
		return;
	std::cerr << statement<<" returned " << cudaGetErrorString(err) << "("<<err<< ") at "<<file<<":"<<line << std::endl;
	exit (EXIT_FAILURE);
}


// Returns a range given the vector by the terminal
void show_vector(int* vector, int min, int max) {
  printf("[%d", vector[min]);
  for (unsigned i = min + 1; i < max; i++) 
    printf(", %d", vector[i]);   
  printf("]\n");
}