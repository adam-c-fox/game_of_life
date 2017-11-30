/*
/   This module is the unpackedWorker for the concurrent Game of Life implementation
/   The implementation stores everything in an array unpacked, with extra columns each,
/   for the neighbouring worker's cells.
/   
/   This module could be improved by packing communications between workers, but this is undecided
/   as it as not been benchmarked.
*/

void unpackedWorker(int id, chanend dist_in, chanend c_left, chanend c_right);
