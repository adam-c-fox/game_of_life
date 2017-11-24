// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include <assert.h>
#include <string.h>

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width
#define  noOfThreads 2			  //Our implementation requires that this must be 2^n

typedef unsigned char uchar;      //using uchar as shorthand
typedef enum { false, true } bool; 

on tile[0]: port p_scl = XS1_PORT_1E;         //interface ports to orientation
on tile[0]: port p_sda = XS1_PORT_1F;
on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for  orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6



//DISPLAYS an LED pattern
int showLEDs(out port p, chanend fromDistributor) {
  int pattern; //1st bit...separate green LED
               //2nd bit...blue LED
               //3rd bit...green LED
               //4th bit...red LED
  while (1) {
    fromDistributor :> pattern;   //receive new pattern
    p <: pattern;                //send pattern to LED port
  }
  return 0;
}

//READ BUTTONS and send button pattern to userAnt
void buttonListener(in port b, chanend toDistributor) {
  int r;
  while (1) {
    b when pinseq(15)  :> r;    
    b when pinsneq(15) :> r;    
    if ((r==13) || (r==14)) {
    	toDistributor <: r;	
    }  
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////

void DataInStream(char infname[], chanend c_out) {
  int res;
  uchar line[IMWD];
  //printf("DataInStream: Start...\n");

  //Open PGM file
  res = _openinpgm(infname, IMWD, IMHT);
  if (res) {
    printf("DataInStream: Error openening %s\n.", infname);
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for (int y = 0; y < IMHT; y++) {
    _readinline(line, IMWD);
    for (int x = 0; x < IMWD; x++) {
      c_out <: line[x];
      //printf("-%4.1d ", line[x]); //show image values
    }
    //printf("\n");
  }

  //Close PGM image file
  _closeinpgm();
  //printf("DataInStream: Done...\n");
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Packed worker functions. 
//
/////////////////////////////////////////////////////////////////////////////////////////

struct packedChunk {
    uchar left, right, top, bottom;
    uchar row[8];
};
typedef struct packedChunk pChunk;

uchar pack(uchar cells[8]) {
    uchar result = 0;
    for (int i = 0; i < 8; i++) {
        result = (result << 1) | (cells[i] & 1);
    }
    return result;
}

void unpack(uchar x, uchar cells[8]) {
    for (int i = 0; i < 8; i++) {
        cells[i] = (x >> (7 - i)) & 1;
    }
}

uchar extract(int n, uchar x) {
    return (x >> (7-n)) & 1;
}

int sumGroup(int x, int y, int x_min, int x_max, int y_min, int y_max, pChunk c) {
    int sum = 0;
    for (int j = y_min; j < y_max; j++) {
        for (int i = x_min; i < x_max; i++) {        	
        	//printf("sum: %d\n", sum);
            if ((i != 1) && (j != 1)) sum += extract(i + x - 1, c.row[j + y - 1]);
        } 
    }
    //printf("sum: %d\n", sum);
    return sum;
}

uchar sumNeighborsPacked(int x, int y, pChunk c) {
    int sum = 0;
    int bottom = 0, left = 0, top = 3, right = 3;


    if (x == 0) {
        for (int j = 0; j < 3; j++) {
            sum += extract(y + j, c.left);
        }

        left = 1;
    }
    if (x == 7) {
        for (int j = 0; j < 3; j++) {
            sum += extract(y + j, c.right);
        }

        right = 2;
    }
    if (y == 0) {
		for (int i = 0; i < 3; i++) {
            sum += extract(x + i, c.bottom);
        }

        bottom = 1;    	
    }
    if (y == 7) {
		for (int i = 0; i < 3; i++) {
            sum += extract(x + i, c.top);
        }

        top = 1;    	
    }

    //printf("x: %d | y: %d\n", x, y);
    //printf("sum: %d\n", sum);
    sum += sumGroup(x, y, left, right, bottom, top, c);

    return sum;
}

pChunk copyPChunk(pChunk c) {
    pChunk pre;

    for (int i = 0; i < 8; i++) {
       pre.row[i] = c.row[i];
    }

    c.left = pre.left;
    c.right = pre.right;
    c.top = pre.top;
    c.bottom = pre.bottom;

    return pre;
}

//TODO change struct passing to pass by reference
pChunk iteratePChunk(pChunk c) {
    pChunk pre = copyPChunk(c);

    // for (int i = 0; i<8; i++) {
    // 	printf("%d | %d\n", c.row[i], pre.row[i]);
    // }

    int count = 0;
    
    for (int y = 0; y < 8; y++) {
        uchar result = 0;
        for (int x = 0; x < 8; x++) { 
            uchar n = sumNeighborsPacked(x, y, pre);
            
            if (n>0) count++;

            //if (x == 4 && y == 7) printf("n: %d\n", n);
            uchar new = 0;

            if (n < 2) new = 0;
            if (n == 2 || n == 3)  new = extract(x, pre.row[y]); // think carefully about this
            if (n > 3) new = 0;
            if (n == 3) new = 1;

            //if (new != 0) printf("new: %d\n", new);
            result = result | new << x;
        }
        c.row[y] = result;
        //printf("c.row[y]: %d\n", c.row[y]);
    }
    //printf("count: %d\n", count);
    return c;
}


//Iterate an array section
void iteratePacked(pChunk array[IMHT/8][(IMWD/noOfThreads)/8]) {
    for (int y = 0; y < IMHT/8; y++) {
        for (int x = 0; x < (IMWD/noOfThreads)/8; x++) {
            array[y][x] = iteratePChunk(array[y][x]);    
        } 
    }
}

//Read in corresponding segment of world
void readInPacked(chanend dist, pChunk grid[IMHT/8][(IMWD/noOfThreads)/8]) {
	uchar temp;

    for (int y = 0; y < IMHT/8; y++) {
        for (int x = 0; x < (IMWD/noOfThreads)/8; x++){
            for (int j = 0; j < 8; j++) {
                uchar buffer[8];
                for (int i = 0; i < 8; i++) {
                    dist :> temp;

                    if (temp == 255) buffer[i] = 1; //May not be needed
                    else buffer[i] = 0;
                }
                grid[y][x].row[j] = pack(buffer);
            }
        }
    }
}

//Send out corresponding segment of world
void sendOutPacked(chanend dist, pChunk grid[IMHT/8][(IMWD/noOfThreads)/8]) {
    for (int y = 0; y < IMHT/8; y++) {
        for (int x = 0; x < (IMWD/noOfThreads)/8; x++){
            for (int j = 0; j < 8; j++) {
                uchar buffer[8];
                unpack(grid[y][x].row[j], buffer); 
                for (int i = 0; i < 8; i++) {
                	//printf("sendOutPacked_here\n");

                    dist <: (uchar)(buffer[i] * 255);
                }
            }
        }
    }
}

uchar getRow(int n, pChunk c) {
    uchar result = 0;
    for (int i = 0; i < 8; i++) {
        result | (c.row[i] & 1) << i;
    }
    return result;
}

void linkChunks(pChunk grid[IMHT/8][(IMWD/noOfThreads)/8]) {
    for (int y = 1; y < IMHT/8 - 1; y++) {
        for (int x = 1; x < (IMWD/noOfThreads)/8 - 1; x++) {
            grid[y][x].left = getRow(7, grid[y][x]);
            grid[y][x].right = getRow(0, grid[y][x]);
            grid[y][x].bottom = grid[y - 1][x].row[7];
            grid[y][x].top = grid[y + 1][x].row[0];
        }
    }

    for (int x = 1; x < (IMWD/noOfThreads)/8; x++) {
        grid[IMHT/8 - 1][x].top = grid[0][x].row[0];
        grid[0][x].bottom = grid[IMHT/8 - 1][x].row[7];
    }
    
}

void passFirst(pChunk grid[IMHT/8][(IMWD/noOfThreads)/8], chanend c_left, chanend c_right) {
    int last = (IMWD/noOfThreads)/8 - 1;
    for (int y = 0; y < IMHT/8; y++) {
        c_left  <: getRow(0, grid[y][0]);
		c_right :> grid[y][last].right;        

        c_right <: getRow(7, grid[y][last]);
        c_left  :> grid[y][0].left;        
    }
}

void receiveFirst(pChunk grid[IMHT/8][(IMWD/noOfThreads)/8], chanend c_left, chanend c_right) {
    int last = (IMWD/noOfThreads)/8 - 1;
    for (int y = 0; y < IMHT/8; y++) {
    	c_right :> grid[y][last].right;
        c_left  <: getRow(0, grid[y][0]);

        c_left  :> grid[y][0].left;
        c_right <: getRow(7, grid[y][last]);
    }
}

void colWorkerPacked(int id, chanend dist_in, chanend c_left, chanend c_right) {
    pChunk grid[IMHT/8][(IMWD/noOfThreads)/8];
    readInPacked(dist_in, grid);    


    
    // for (int i = 0; i<8; i++) {
    // 	printf("%d: row: %d\n", i, grid[0][0].row[i]);	
    // }  

    bool iterating = true;

    while (1) {
    	while (iterating) {
	    	linkChunks(grid);

	        if ((id % 2) == 0) {
	            passFirst(grid, c_left, c_right);
	        }
	        else {
	            receiveFirst(grid, c_left, c_right);
	        } 

	        iteratePacked(grid);

	        dist_in <: 1;
	        dist_in :> iterating;

    	}	

	    int proceed;
	    dist_in :> proceed;

	    sendOutPacked(dist_in, grid); //deadlock in here
	    iterating = true;
    }
 
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Worker functions. 
//
/////////////////////////////////////////////////////////////////////////////////////////


//Total number of neighbors of a cell
uchar sumNeighbors(uchar pre[IMHT][(IMWD/noOfThreads)+2], int x, int y) {
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
void iterate(uchar array[IMHT][(IMWD/noOfThreads)+2]) {
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
void sendOut(chanend dist_in, uchar grid[IMHT][IMWD/noOfThreads+2]) {
    int colWidth = (IMWD/noOfThreads);
    for (int y = 0; y<IMHT; y++) {
        for (int x = 1; x <= colWidth; x++){
            dist_in <: grid[y][x];
        }
    }
}

//Read in corresponding segment of world
void readIn(chanend dist_in, uchar grid[IMHT][IMWD/noOfThreads+2]) {
    int colWidth = (IMWD/noOfThreads);
    for (int y = 0; y<IMHT; y++) {
        for (int x = 1; x <= colWidth; x++){
            dist_in :> grid[y][x];
        }
    }
}


void colWorker(int id, chanend dist_in, chanend c_left, chanend c_right) {
    int colWidth = (IMWD/noOfThreads); //Adam remember to remove if needed
    uchar grid[IMHT][(IMWD/noOfThreads)+2];

    readIn(dist_in, grid);

    bool iterating = true;
    while (iterating) {
        //If even column: pass to right, then read from left
        //If odd column : read from left, then pass to right
        if ((id % 2) == 0) {
            for (int y = 0; y<IMHT; y++) {
                c_right <: grid[y][colWidth];
                c_left  :> grid[y][0];

                c_right :> grid[y][colWidth+1];
                c_left  <: grid[y][1];
            }
        }
        else {
            for (int y = 0; y<IMHT; y++) {
                c_left :> grid[y][0];
                c_right <: grid[y][colWidth];

                c_left  <: grid[y][1];
                c_right :> grid[y][colWidth+1];
            }
        } 

        iterate(grid);

        dist_in <: 1;
        dist_in :> iterating;
    }

    int proceed;
    dist_in :> proceed;

    sendOut(dist_in, grid); 
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Distributor functions. 
//
/////////////////////////////////////////////////////////////////////////////////////////


//Reads in image and passes to the correct worker
void passInitialState(chanend c_in, chanend fromWorker[noOfThreads]) {
    printf("Reading in image...\n");

    uchar temp;
    for (int y = 0; y < IMHT; y++) {  
        for (int n = 0; n < noOfThreads; n++) {
            for (int x = 0; x < (IMWD/noOfThreads); x++) { 
	        c_in :> temp;
            fromWorker[n] <: temp;                    
            }
        }
    }
    printf("Image read in successfully.\n");
}

//Collects in results from workers and sends to output
void passOutputState(chanend c_out, chanend fromWorker[noOfThreads]) {
    printf("Button press confirmed, saving image...\n");

    for (int i = 0; i<noOfThreads; i++) {
    	fromWorker[i] <: 1;
    }

    uchar temp;
    for (int y = 0; y < IMHT; y++) {
        for (int n = 0; n < noOfThreads; n++) {
            for (int x = 0; x < (IMWD/noOfThreads); x++) { 
            	//printf("passOutputState_here\n");

                fromWorker[n] :> temp;                    
                c_out <: temp;
            }
        }
    }

}

void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend fromWorker[noOfThreads], chanend fromButtons, chanend toLEDs) {
    printf("ProcessImage: Start, size = %dx%d\n", IMHT, IMWD);

    int value = 0;

    while (value != 14) {
       	printf("Proceed with launch?\n");
    	fromButtons :> value;
    }
    
    toLEDs <: 1;

    passInitialState(c_in, fromWorker); 

    int closed = 0, count = 0, liveCells = 0, timeElapsed = 0, confirm;
    bool iterating = true, paused = false;
    printf("Terminate at will...\n");

    int ledPattern = 5;

    while (1) {
    	while (closed < noOfThreads) {
	    	// select {
	    	// 	    case fromAcc :> confirm:
	    	// 	    	if (confirm == 1) {
	    	// 	    		paused = true;
	    	// 	    		toLEDs <: 8; //red LED

	    	// 	    		printf("\n--------<STATUS REPORT>--------\n");
	    	// 	    		printf("Rounds processed:        %d\n", count);
	    	// 	    		printf("Live cells:              %d\n", liveCells);
	    	// 	    		printf("Processing time elapsed: %d\n", timeElapsed);
	    	// 	    		printf("-------------------------------\n");
	    	// 	    	}
	    	// 	    	else paused = false;
	    	// 		break; 
	    	// }


	    	//if (!paused) {
		    	select {
		    		case fromWorker[int i] :> confirm:
		    			if (iterating) fromWorker[i] <: true;
		    			else {
		    				fromWorker[i] <: false;
		    				closed++;
		    			}

		    			if (i == 0) {
		    				toLEDs <: ledPattern;
		    				count++;

		    				if (ledPattern == 5) ledPattern = 1;
		    				else ledPattern = 5;
		    			}
		    			break;
		    		case fromButtons :> confirm:
		    			if (confirm == 13) iterating = false;	
		    			break;	
		    	}
	    	//}
			
	    }

	    toLEDs <: 2; //Blue when exporting image
		passOutputState(c_out, fromWorker);
		toLEDs <: 0;    		

		iterating = true;
		closed = 0;

    }
    

    
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////

void DataOutStream(char outfname[], chanend c_in) {
  int res, count = 1;
  char name[128];
  

  uchar line[IMWD];


  while (1) {
  	sprintf(name, "%s%d.pgm", outfname, count);
	  //Open PGM file
  	printf("DataOutStream: Start...\n");
  	res = _openoutpgm(name, IMWD, IMHT);
  	if (res) {
  		printf("DataOutStream: Error opening %s\n.", outfname);
  	}

	  //Compile each line of the image and write the image line-by-line
  	for (int y = 0; y < IMHT; y++) {
  		for (int x = 0; x < IMWD; x++) {
  			c_in :> line[x];
  		}
  		_writeoutline(line, IMWD);
	    //printf("DataOutStream: Line written...\n");
  	}

	//Close the PGM image
  	_closeoutpgm();
  	printf("Image saved.\n");
  	count++;
  }
  
 }

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////

void orientation(client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;
  int tilted = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis for ever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (!tilted) {
      if (x>30) {
        tilted = 1 - tilted;
        toDist <: 1;
      }


      //TEST
      //SEND SIGNAL WHEN TILTING CEASES
      if (x<30) { 
      	tilted = 0;
      	toDist <: 0;
      }
    }
  }
}


void set(uchar a[8], uchar v0, uchar v1, uchar v2, uchar v3, uchar v4, uchar v5, uchar v6, uchar v7) {
    a[0] = v0; a[1] = v1; a[2] = v2; a[3] = v3; a[4] = v4; a[5] = v5; a[6] = v6; a[7] = v7;
}

void printByteRow(uchar a[8]) {
    printf("[");
    for (int i = 0; i < 7; i++) {
        printf("%d,", a[i]);
    }
    printf("%d", a[7]);
    printf("]\n");
}


void testPack() {
    uchar test[8];
    set(test,0,0,0,0,0,0,0,0);
    assert(pack(test) == 0);
    set(test,0,0,0,0,0,0,0,1);
    assert(pack(test) == 1);
    set(test,1,0,0,0,0,0,0,0);
    assert(pack(test) == 128);
    set(test,0,0,0,0,0,0,0,255);
    assert(pack(test) == 1);
    set(test,0,0,0,0,0,0,1,0);
    assert(pack(test) == 2);
    set(test,1,1,1,1,1,1,1,1);
    assert(pack(test) == 255);
    set(test,0,0,0,1,0,0,1,0);
    assert(pack(test) == 18);
    set(test,0,0,0,255,0,0,255,0);
    assert(pack(test) == 18);
}

void testUnpack() {
    uchar expected[8];
    uchar result[8];
    int test;

    set(expected,0,0,0,0,0,0,0,0);
    unpack(0, result);
    test = memcmp(result, expected, 8);
    assert(test == 0);

    set(expected,0,0,0,0,0,0,0,1);
    unpack(1, result);
<<<<<<< HEAD
    test = memcmp(result, expected, 8);
    assert(test == 0);
=======
    //assert(memcmp(result, expected, 8) == 0);
>>>>>>> 9317f6661c6d821a32337a7c8977c3b00abcea4d
    
    set(expected,1,0,0,0,0,0,0,0);
    unpack(128, result);
    test = memcmp(result, expected, 8);
    assert(test == 0);
    
    set(expected,1,0,0,0,0,0,0,1);
    unpack(129, result);
    test = memcmp(result, expected, 8);
    assert(test == 0);
    
    set(expected,1,1,1,1,1,1,1,1);
    unpack(255, result);
    test = memcmp(result, expected, 8);
    assert(test == 0);
}

void test() {
    testPack();
    testUnpack();
    printf("All tests pass!\n");
}



/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {
    i2c_master_if i2c[1];               //interface to orientation
    chan c_inIO, c_outIO, c_control;
    chan c_buttons, c_leds;

    
    //colWorker channels
    chan worker[noOfThreads], dist[noOfThreads];
    
    par {
        on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
        on tile[0]: orientation(i2c[0],c_control);        //client thread reading orientation data
        on tile[1]: DataInStream("test.pgm", c_inIO);          //thread to read in a PGM image
        on tile[1]: DataOutStream("testout", c_outIO);       //thread to write out a PGM image
        on tile[1]: distributor(c_inIO, c_outIO, c_control, dist, c_buttons, c_leds);//thread to coordinate work on image


        on tile[0]: test();
        on tile[0]: buttonListener(buttons, c_buttons);
        on tile[0]: showLEDs(leds, c_leds);
    
        // on tile[0]: par (int i = 0; i < (noOfThreads/2); i++) {
        //     colWorkerPacked(i, dist[i], worker[i], worker[(i+1)%noOfThreads]);
        // }

        // on tile[1]: par (int i = 4; i < noOfThreads; i++) {
        //     colWorkerPacked(i, dist[i], worker[i], worker[(i+1)%noOfThreads]);
        // }

        on tile[1]: colWorkerPacked(0, dist[0], worker[0], worker[1]);
        on tile[1]: colWorkerPacked(1, dist[1], worker[1], worker[0]);
    }

    return 0;
}
