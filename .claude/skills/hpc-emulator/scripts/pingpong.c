/* Tiny MPI ping-pong: rank 0 <-> rank 1, prints half round-trip in us. */
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  MPI_Init(&argc, &argv);
  int rank, size;
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);
  MPI_Comm_size(MPI_COMM_WORLD, &size);
  if (size < 2) { if (rank == 0) fprintf(stderr, "need >=2 ranks\n"); MPI_Finalize(); return 1; }

  const int iters = 2000;
  const int warmup = 200;
  const int msg_bytes = 8;
  char *buf = (char *)malloc(msg_bytes);
  memset(buf, 0, msg_bytes);

  /* Warmup */
  for (int i = 0; i < warmup; i++) {
    if (rank == 0) { MPI_Send(buf, msg_bytes, MPI_BYTE, 1, 0, MPI_COMM_WORLD);
                     MPI_Recv(buf, msg_bytes, MPI_BYTE, 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE); }
    else if (rank == 1) { MPI_Recv(buf, msg_bytes, MPI_BYTE, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
                          MPI_Send(buf, msg_bytes, MPI_BYTE, 0, 0, MPI_COMM_WORLD); }
  }
  MPI_Barrier(MPI_COMM_WORLD);

  double t0 = MPI_Wtime();
  for (int i = 0; i < iters; i++) {
    if (rank == 0) { MPI_Send(buf, msg_bytes, MPI_BYTE, 1, 0, MPI_COMM_WORLD);
                     MPI_Recv(buf, msg_bytes, MPI_BYTE, 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE); }
    else if (rank == 1) { MPI_Recv(buf, msg_bytes, MPI_BYTE, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
                          MPI_Send(buf, msg_bytes, MPI_BYTE, 0, 0, MPI_COMM_WORLD); }
  }
  double t1 = MPI_Wtime();

  if (rank == 0) {
    double half_rt_us = (t1 - t0) * 1e6 / (2.0 * iters);
    printf("pingpong: %d iters, %d bytes, half-RT = %.3f us (one-way)\n",
           iters, msg_bytes, half_rt_us);
  }
  free(buf);
  MPI_Finalize();
  return 0;
}
