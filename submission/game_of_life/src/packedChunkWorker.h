/* 
/   This is the packedChunkWorker for the concurrent Game of Life implementation
/   Each section that the worker reads in, is stored in 8x8 'chunks', which are 
/   iterated on indervidually.
/   
/   This module's could be improved through packing into ints instead of uchars.
*/

void packedChunkWorker(int id, chanend dist_in, chanend c_left, chanend c_right);
void testPackedChunkWorker();
