typedef unsigned char uchar;      //using uchar as shorthand

uchar pack(uchar cells[8]);
void colWorkerPacked(int id, chanend dist_in, chanend c_left, chanend c_right);
void testPackedChunkWorker();
