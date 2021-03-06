/* 
/   This is the packedChunkWorker for the concurrent Game of Life implementation
/   Each section that the worker reads in, is stored in 8x8 'chunks', which are 
/   iterated on indervidually.
/   
/   This module's could be improved through packing into ints instead of uchars.
*/

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include <assert.h>
#include <string.h>
#include "config.h"
#include "utility.h"
#include "packedChunkWorker.h"


struct packedChunk {
    uchar left, right, top, bottom, corners;
    uchar row[8];
};
typedef struct packedChunk pChunk;


//Debugging function for drawing a gird
static void drawGrid(pChunk grid[IMHT/8][(IMWD/noOfThreads)/8]) {
    for (int yG = 0; yG < (IMHT/8); yG++) {

        //tops
        printf("   "); 
        for (int xG = 0; xG < (IMWD/noOfThreads)/8; xG++) {
            for (int i = 0; i<8; i++) {
                printf("%d ", extract(i, grid[yG][xG].top));
            }
            printf("    "); //4 
        }
        printf("\n");


        //rows
        for (int i = 0; i<8; i++) {
            for (int xG = 0; xG < (IMWD/noOfThreads)/8; xG++) {
                printf("%d  ", extract(i, grid[yG][xG].left));

                for (int j = 0; j<8; j++) {
                   printf("%d ", extract(j, grid[yG][xG].row[i])); 
                }
                
                printf(" %d", extract(i, grid[yG][xG].right));
            }
            
            printf("\n");
        }

        //bottom
        printf("   "); //3
        for (int xG = 0; xG < (IMWD/noOfThreads)/8; xG++) {
            for (int i = 0; i<8; i++) {
                printf("%d ", extract(i, grid[yG][xG].bottom));
            }
            printf("    "); //4 
        }
        printf("\n\n");

    }


}


//Sums the 8 squares neighbouring x,y in the ordinarry parts of a packed chunk
//It is the responsibility of the caller to deal with chunk edge cases
static int sumGroup(int x, int y, int x_min, int x_max, int y_min, int y_max, pChunk c) {
    int sum = 0;
    for (int j = y_min; j <= y_max; j++) {
        for (int i = x_min; i <= x_max; i++) {        	
            if (i != x || j != y) sum += extract(i, c.row[j]);
        } 
    }
    return sum;
}

//Sums an edge case, will add leftmost corner if boolean takeLeft is true 
static int sumEdge(int n, uchar edge, uchar corner, bool takeLeft) {
    int sum = 0;

    if (n == 0) {
        for (int i = 0; i < 2; i++) {
            sum += extract(n + i, edge);
        }
        if (takeLeft) sum += corner;
    }    
    else if (n == 7) {
        for (int i = -1; i < 1; i++) {
            sum += extract(n + i, edge);
        }
        if (!takeLeft) sum += corner;
    }
    else {
        for (int i = -1; i < 2; i++) {
            sum += extract(n + i, edge);
        }
    }

    return sum;
}

//Sums all the neighbours x,y in a chunk
static uchar sumNeighborsPacked(int x, int y, pChunk c) {
    int sum = 0;
    int bottom = y+1, left = x-1, top = y-1, right = x+1;

    //Edges
    if (left < 0) {
        sum += sumEdge(y, c.left, extract(0, c.corners), true);
        left++;
    }    
    if (right > 7) {
        sum += sumEdge(y, c.right, extract(2, c.corners), false);
        right--;
    }
    if (top < 0) {
    	sum += sumEdge(x, c.top, extract(1, c.corners), false);
        top++;
    }
    if (bottom > 7) {
    	sum += sumEdge(x, c.bottom, extract(3, c.corners), true);
        bottom--;            	
    }

    sum += sumGroup(x, y, left, right, top, bottom, c);
    return sum;
}

//Calculates the sum of the neighbours iterates based on game of life rules
static pChunk iteratePChunk(pChunk c) {
    pChunk pre = c;

    for (int y = 0; y < 8; y++) {
        uchar result = 0;
        for (int x = 0; x < 8; x++) { 
            uchar n = sumNeighborsPacked(x, y, pre);
            uchar new = 0;

            if (n < 2) new = 0;
            else if (n == 2) new = extract(x, pre.row[y]); 
            else if (n == 3) new = 1;
            else new = 0;

            result = (result << 1) | (new & 1);
        }
        c.row[y] = result;
    }
    return c;
}


//Iterate through every chunk of the array
static void iteratePacked(int id, pChunk array[IMHT/8][(IMWD/noOfThreads)/8]) {
    for (int y = 0; y < IMHT/8; y++) {
        for (int x = 0; x < (IMWD/noOfThreads)/8; x++) {
            array[y][x] = iteratePChunk(array[y][x]);
        } 
    }
}

//Read in corresponding segment of world
static void readInPacked(chanend dist, pChunk grid[IMHT/8][(IMWD/noOfThreads)/8]) {
	for (int y = 0; y < IMHT; y++) {
        for (int x = 0; x < IMWD/noOfThreads/8; x++) {
            uchar result;
            uchar buffer[8];
            for (int i = 0; i < 8; i++) {
                dist :> result;
                buffer[i] = result ? 1 : 0;
            }
            grid[y/8][x].row[y%8] = pack(buffer);
        }
    }
}

//Sends out corresponding segment of world
static void sendOutPacked(chanend dist, pChunk grid[IMHT/8][(IMWD/noOfThreads)/8]) {
     for (int y = 0; y < IMHT/8; y++) {
         for (int j = 0; j < 8; j++) {
             for (int x = 0; x < (IMWD/noOfThreads)/8; x++){
                 uchar buffer[8];
                 unpack(grid[y][x].row[j], buffer); 
                 for (int i = 0; i < 8; i++) {
                     dist <: (uchar)(buffer[i] * 255);
                 }
             }
         }
     }
}

//Returns column n stored in a chunk
static uchar getCol(int n, pChunk c) {
    uchar result = 0;
    for (int i = 0; i < 8; i++) {
        result = (result << 1) | (extract(n, c.row[i]) & 1);
    }
    return result;
}

//Fills in the corner field of each chunk
//This implementation requires that the edges have correct values
//This also requires that thread communication has already taken place
static void linkCorners(pChunk grid[IMHT/8][(IMWD/noOfThreads)/8]) {
    uchar cornersArray[8] = {0, 0, 0, 0};

    for (int y = 1; y < IMHT/8 - 1; y++) {
        for (int x = 0; x < (IMWD/noOfThreads)/8; x++) {
            cornersArray[0] = extract(7, grid[y-1][x].left);
            cornersArray[1] = extract(7, grid[y-1][x].right);

            cornersArray[2] = extract(0, grid[y+1][x].right);
            cornersArray[3] = extract(0, grid[y+1][x].left);

            grid[y][x].corners = pack(cornersArray);            
        }
    }

    //Top
    for (int x = 0; x < (IMWD/noOfThreads)/8; x++) {
        cornersArray[0] = extract(7, grid[(IMHT/8)-1][x].left);
        cornersArray[1] = extract(7, grid[(IMHT/8)-1][x].right);

        cornersArray[2] = extract(0, grid[1][x].right);
        cornersArray[3] = extract(0, grid[1][x].left);

        grid[0][x].corners = pack(cornersArray);
    }

    //Bottom
    for (int x = 0; x < (IMWD/noOfThreads)/8; x++) {
        cornersArray[0] = extract(7, grid[(IMHT/8)-2][x].left);
        cornersArray[1] = extract(7, grid[(IMHT/8)-2][x].right);

        cornersArray[2] = extract(0, grid[0][x].right);
        cornersArray[3] = extract(0, grid[0][x].left);

        grid[(IMHT/8)-1][x].corners = pack(cornersArray);
    }

}

//Fills in the edges for each chunk, then calls linkCorners
static void linkChunks(pChunk grid[IMHT/8][(IMWD/noOfThreads)/8]) {
   for (int y = 0; y < IMHT/8; y++) {
        for (int x = 0; x < (IMWD/noOfThreads)/8; x++) {
            if (x != 0)                        grid[y][x].left = getCol(7, grid[y][x-1]);
            if (x != ((IMWD/noOfThreads)/8)-1) grid[y][x].right = getCol(0, grid[y][x+1]);
            if (y != 0)                        grid[y][x].top = grid[y-1][x].row[7];
            if (y != (IMHT/8)-1)               grid[y][x].bottom = grid[y+1][x].row[0];
        }
    }

    for (int x = 0; x < (IMWD/noOfThreads)/8; x++) {
        grid[IMHT/8 - 1][x].bottom = grid[0][x].row[0];
        grid[0][x].top = grid[IMHT/8 - 1][x].row[7];
    }


    linkCorners(grid);
}

//Pass and recieve edges to the thread on left and right, passing first
static void passFirst(pChunk grid[IMHT/8][(IMWD/noOfThreads)/8], chanend c_left, chanend c_right) {
    int last = (IMWD/noOfThreads)/8 - 1;
    for (int y = 0; y < IMHT/8; y++) {
        c_left  <: getCol(0, grid[y][0]);
	c_right :> grid[y][last].right;        

        c_right <: getCol(7, grid[y][last]);
        c_left  :> grid[y][0].left;        
    }
}

//Pass and recieve edges to the thread on left and right, recieving first
static void receiveFirst(pChunk grid[IMHT/8][(IMWD/noOfThreads)/8], chanend c_left, chanend c_right) {
    int last = (IMWD/noOfThreads)/8 - 1;
    for (int y = 0; y < IMHT/8; y++) {
    	c_right :> grid[y][last].right;
        c_left  <: getCol(0, grid[y][0]);

        c_left  :> grid[y][0].left;
        c_right <: getCol(7, grid[y][last]);
    }
}

//Counts the number of live cells stored by this worker
static int sumLive(pChunk grid[IMHT/8][(IMWD/noOfThreads)/8]) {
    int sum = 0;
    for (int y = 0; y < IMHT; y++) {
        for (int x = 0; x < (IMWD/noOfThreads); x++){
            if (extract(x % 8, grid[y/8][x/8].row[y % 8])) sum++;
        }
    }
    return sum;
}

void packedChunkWorker(int id, chanend dist_in, chanend c_left, chanend c_right) {
    pChunk grid[IMHT/8][(IMWD/noOfThreads)/8];
    readInPacked(dist_in, grid);    

    bool iterating = true;

    while (1) {
        while (iterating) {

    	    if ((id % 2) == 0) {
    	        passFirst(grid, c_left, c_right);
    	    }
    	    else {
    	        receiveFirst(grid, c_left, c_right);
    	    } 

            linkChunks(grid);
            iteratePacked(id, grid);
            
            dist_in <: 1;
    	    dist_in :> iterating;

        }	
        
        dist_in <: sumLive(grid);

	int sendingOut;
	dist_in :> sendingOut;

        if (sendingOut == 1) {
            sendOutPacked(dist_in, grid); 
        }

	iterating = true;
    }
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Testing.
//
/////////////////////////////////////////////////////////////////////////////////////////

static void set(uchar a[8], uchar v0, uchar v1, uchar v2, uchar v3, uchar v4, uchar v5, uchar v6, uchar v7) {
    a[0] = v0; a[1] = v1; a[2] = v2; a[3] = v3; a[4] = v4; a[5] = v5; a[6] = v6; a[7] = v7;
}

static void printByteRow(uchar a[8]) {
    printf("[");
    for (int i = 0; i < 7; i++) {
        printf("%d,", a[i]);
    }
    printf("%d", a[7]);
    printf("]\n");
}

static void testSumNeighbors() {
    pChunk test;
    pChunk testBelow;
    test.left = 0;
    test.right = 0;
    test.top = 0; 
    test.bottom = 0; 
    test.corners = 0; 
    set(test.row,0,0,0,0,0,0,0,0);
    assert(sumNeighborsPacked(5,5,test) == 0);
    assert(sumNeighborsPacked(0,5,test) == 0);
    assert(sumNeighborsPacked(5,0,test) == 0);
    assert(sumNeighborsPacked(0,0,test) == 0);
    assert(sumNeighborsPacked(7,0,test) == 0);
    assert(sumNeighborsPacked(7,7,test) == 0);

    test.left = 0;
    test.right = 0;
    test.top = 0; 
    test.bottom = 0; 
    test.corners = 0; 
    set(test.row,0,0,0,0,0,8,4,28);
    assert(sumNeighborsPacked(2,4,test) == 0);
    assert(sumNeighborsPacked(2,5,test) == 0);
    assert(sumNeighborsPacked(2,6,test) == 1);
    assert(sumNeighborsPacked(2,7,test) == 1);
    
    assert(sumNeighborsPacked(3,4,test) == 1);
    assert(sumNeighborsPacked(3,5,test) == 1);
    assert(sumNeighborsPacked(3,6,test) == 3);
    assert(sumNeighborsPacked(3,7,test) == 1);

    assert(sumNeighborsPacked(4,4,test) == 1);
    assert(sumNeighborsPacked(4,5,test) == 1);
    assert(sumNeighborsPacked(4,6,test) == 5);
    assert(sumNeighborsPacked(4,7,test) == 3);

    assert(sumNeighborsPacked(5,4,test) == 1);
    assert(sumNeighborsPacked(5,5,test) == 2);
    assert(sumNeighborsPacked(5,6,test) == 3);
    assert(sumNeighborsPacked(5,7,test) == 2);

    assert(sumNeighborsPacked(6,4,test) == 0);
    assert(sumNeighborsPacked(6,5,test) == 1);
    assert(sumNeighborsPacked(6,6,test) == 2);
    assert(sumNeighborsPacked(6,7,test) == 2);

    assert(sumNeighborsPacked(7,4,test) == 0);
    assert(sumNeighborsPacked(7,5,test) == 0);
    assert(sumNeighborsPacked(7,6,test) == 0);
    assert(sumNeighborsPacked(7,7,test) == 0);

    testBelow.left = 0;
    testBelow.right = 0;
    testBelow.top = 28; 
    testBelow.bottom = 0; 
    testBelow.corners = 0; 
    set(testBelow.row,0,0,0,0,0,0,0,0);
    assert(sumNeighborsPacked(0,0,testBelow) == 0);
    assert(sumNeighborsPacked(1,0,testBelow) == 0);
    assert(sumNeighborsPacked(2,0,testBelow) == 1);
    assert(sumNeighborsPacked(3,0,testBelow) == 2);
    assert(sumNeighborsPacked(4,0,testBelow) == 3);
    assert(sumNeighborsPacked(5,0,testBelow) == 2);
    assert(sumNeighborsPacked(6,0,testBelow) == 1);
    assert(sumNeighborsPacked(7,0,testBelow) == 0);

    assert(sumNeighborsPacked(0,1,testBelow) == 0);
    assert(sumNeighborsPacked(1,1,testBelow) == 0);
    assert(sumNeighborsPacked(2,1,testBelow) == 0);
    assert(sumNeighborsPacked(3,1,testBelow) == 0);
    assert(sumNeighborsPacked(4,1,testBelow) == 0);
    assert(sumNeighborsPacked(5,1,testBelow) == 0);
    assert(sumNeighborsPacked(6,1,testBelow) == 0);
    assert(sumNeighborsPacked(7,1,testBelow) == 0);
} 


static void testLinkChunks() {
    pChunk array[IMHT/8][(IMWD/noOfThreads)/8];
    pChunk test;
    pChunk testBelow;
    test.left = 0;
    test.right = 0;
    test.top = 0; 
    test.bottom = 0; 
    test.corners = 0; 
    set(test.row,0,0,0,0,0,8,4,28);
    array[0][0] = test;

    testBelow.left = 0;
    testBelow.right = 0;
    testBelow.top = 0; 
    testBelow.bottom = 0; 
    testBelow.corners = 0; 
    set(testBelow.row,0,0,0,0,0,0,0,0);
    array[1][0] = testBelow;
    linkChunks(array);
    assert(extract(3,array[1][0].top) == 1);
    assert(extract(4,array[1][0].top) == 1);
    assert(extract(5,array[1][0].top) == 1);
    assert(extract(0,array[1][0].top) == 0);
    assert(extract(1,array[1][0].top) == 0);
    assert(extract(2,array[1][0].top) == 0);
    assert(extract(6,array[1][0].top) == 0);
    assert(extract(7,array[1][0].top) == 0);
   
}
 
static void testIteratePChunk() {
    pChunk new;
    pChunk newBelow;
    pChunk test;
    pChunk testBelow;
    test.left = 0;
    test.right = 0;
    test.top = 0; 
    test.bottom = 0; 
    test.corners = 0; 
    set(test.row,0,0,0,0,0,0,0,0);
    new = iteratePChunk(test);
    assert(extract(3,new.row[2]) == 0);
    assert(extract(4,new.row[5]) == 0);
    assert(extract(3,new.row[0]) == 0);
    assert(extract(6,new.row[7]) == 0);
    assert(extract(7,new.row[7]) == 0);
    assert(extract(0,new.row[0]) == 0);


    assert(extract(1,new.row[0]) == 0);
    assert(extract(2,new.row[0]) == 0);
    assert(extract(3,new.row[0]) == 0);
    assert(extract(4,new.row[0]) == 0);
    assert(extract(5,new.row[0]) == 0);
    assert(extract(6,new.row[0]) == 0);
    assert(extract(7,new.row[0]) == 0);
    assert(extract(0,new.row[0]) == 0);



    test.left = 0;
    test.right = 0;
    test.top = 0; 
    test.bottom = 0; 
    test.corners = 0; 
    set(test.row,0,0,0,0,0,8,4,28);
    new = iteratePChunk(test);
    assert(extract(3,new.row[6]) == 1);
    assert(extract(4,new.row[7]) == 1);
    assert(extract(5,new.row[7]) == 1);
    assert(extract(5,new.row[6]) == 1);
    assert(extract(5,new.row[7]) == 1);
    assert(extract(0,new.row[0]) == 0);

    assert(extract(1,new.row[0]) == 0);
    assert(extract(2,new.row[0]) == 0);
    assert(extract(3,new.row[0]) == 0);
    assert(extract(4,new.row[0]) == 0);
    assert(extract(5,new.row[0]) == 0);
    assert(extract(6,new.row[0]) == 0);
    assert(extract(7,new.row[0]) == 0);
    assert(extract(0,new.row[0]) == 0);



    testBelow.left = 0;
    testBelow.right = 0;
    testBelow.top = 28; 
    testBelow.bottom = 0; 
    testBelow.corners = 0; 
    set(testBelow.row,0,0,0,0,0,0,0,0);
    newBelow = iteratePChunk(testBelow);
    assert(extract(4,newBelow.row[0]) == 1);
    assert(extract(3,newBelow.row[0]) == 0);
    assert(extract(5,newBelow.row[0]) == 0);
    assert(extract(4,newBelow.row[1]) == 0);

    assert(extract(1,new.row[0]) == 0);
    assert(extract(2,new.row[0]) == 0);
    assert(extract(3,new.row[0]) == 0);
    assert(extract(4,new.row[0]) == 0);
    assert(extract(5,new.row[0]) == 0);
    assert(extract(6,new.row[0]) == 0);
    assert(extract(7,new.row[0]) == 0);
    assert(extract(0,new.row[0]) == 0);


    new.bottom = 16;
    newBelow.top = 24;
    new = iteratePChunk(new);
    newBelow = iteratePChunk(newBelow);

    assert(extract(1,new.row[0]) == 0);
    assert(extract(2,new.row[0]) == 0);
    assert(extract(3,new.row[0]) == 0);
    assert(extract(4,new.row[0]) == 0);
    assert(extract(5,new.row[0]) == 0);
    assert(extract(6,new.row[0]) == 0);
    assert(extract(7,new.row[0]) == 0);
    assert(extract(0,new.row[0]) == 0);

}

void testPackedChunkWorker() {
    testSumNeighbors();
    testLinkChunks();
    testIteratePChunk();
}


