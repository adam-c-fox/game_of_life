/*
/   This module is the unpackedWorker for the concurrent Game of Life implementation
/   The implementation stores everything in an array unpacked, with extra columns each,
/   for the neighbouring worker's cells.
/   
/   This module could be improved by packing communications between workers, but this is undecided
/   as it as not been benchmarked.
*/

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include <assert.h>
#include <string.h>
#include "unpackedWorker.h"
#include "config.h"
#include "utility.h"

//Total number of neighbors of a cell
static uchar sumNeighbors(uchar pre[IMHT][(IMWD/noOfThreads)+2], int x, int y) {
    int total = 0;

    for (int a = -1; a <= 1; a++) {
        for (int b = -1; b <= 1; b++) {
          if ((y+b) < 0 && pre[IMHT-1][x+a] != 0) total++;
          else if ((y+b) >= 0 && pre[(y+b) % IMHT][(x+a)] != 0 && !(a == 0 && b == 0)) total++;
        }
    }
    
    return total;
}

//Iterate an array section
static void iterate(uchar array[IMHT][(IMWD/noOfThreads)+2]) {
    int ix = IMWD/noOfThreads;
    uchar pre[IMHT][(IMWD/noOfThreads)+2];

    for (int y = 0; y < IMHT; y++) {
        for (int x = 0; x < (ix+2); x++) {
            pre[y][x] = array[y][x];
        }
    }
    
    for (int y = 0; y < IMHT; y++) {
        for (int x = 1; x <= ix; x++) {
            uchar n = sumNeighbors(pre, x, y);

            if (n < 2) array[y][x] = 0;
            //if (n == 2 || n == 3) // do nothing
            if (n > 3) array[y][x] = 0;
            if (n == 3) array[y][x] = 255;
        }
    }

    //255 = WHITE
    //0   = BLACK
}

//Send out corresponding segment of world
static void sendOut(chanend dist_in, uchar grid[IMHT][IMWD/noOfThreads+2]) {
    int colWidth = (IMWD/noOfThreads);
    for (int y = 0; y<IMHT; y++) {
        for (int x = 1; x <= colWidth; x++){
            dist_in <: grid[y][x];
        }
    }
}

//Read in corresponding segment of world
static void readIn(chanend dist_in, uchar grid[IMHT][IMWD/noOfThreads+2]) {
    int colWidth = (IMWD/noOfThreads);
    for (int y = 0; y<IMHT; y++) {
        for (int x = 1; x <= colWidth; x++){
            dist_in :> grid[y][x];
        }
    }
}

//Pass and recieve edges to the thread on left and right, passing first
static void passFirst(uchar grid[IMHT][(IMWD/noOfThreads)+2], chanend c_left, chanend c_right) {
    int colWidth = (IMWD/noOfThreads); 
    for (int y = 0; y<IMHT; y++) {
        c_right <: grid[y][colWidth];
        c_left  :> grid[y][0];

        c_right :> grid[y][colWidth+1];
        c_left  <: grid[y][1];
    }
}

//Pass and recieve edges to the thread on left and right, recieving first
static void recieveFirst(uchar grid[IMHT][(IMWD/noOfThreads)+2], chanend c_left, chanend c_right) {
    int colWidth = (IMWD/noOfThreads); 
    for (int y = 0; y<IMHT; y++) {
        c_left :> grid[y][0];
        c_right <: grid[y][colWidth];

        c_left  <: grid[y][1];
        c_right :> grid[y][colWidth+1];
    }
}

//Counts the number of live cells stored by this worker
static int sumLive(uchar grid[IMHT][(IMWD/noOfThreads)+2]) {
    int sum = 0;
    for (int y = 0; y < IMHT; y++) {
        for (int x = 1; x < (IMWD/noOfThreads) + 1; x++){
            if (grid[y][x]) sum++;
        }
    }
    return sum;
}

void unpackedWorker(int id, chanend dist_in, chanend c_left, chanend c_right) {
    int colWidth = (IMWD/noOfThreads); 
    uchar grid[IMHT][(IMWD/noOfThreads)+2];

    readIn(dist_in, grid);

    bool iterating = true;
    while (1) {
        while (iterating) {
            //If even column: pass to right, then read from left
            //If odd column : read from left, then pass to right
            if ((id % 2) == 0) {
    	        passFirst(grid, c_left, c_right);
            }
            else {
    	        recieveFirst(grid, c_left, c_right);
            } 

            iterate(grid);

            dist_in <: 1;
            dist_in :> iterating;
        }

        dist_in <: sumLive(grid);

        int sendingOut;
        dist_in :> sendingOut;

        if (sendingOut == 1) {
            sendOut(dist_in, grid); 
        }

        iterating = true;
    }
}
