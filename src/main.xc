// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include <assert.h>

#define  IMHT 512                  //image height
#define  IMWD 512                  //image width
#define  noOfThreads 8 			  //Our implementation requires that this must be 2^n
#define  iterations 1

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

uchar pack(uchar cells[8]) {
    uchar result = 0;
    for (int i = 0; i < 8; i++) {
        result | cells[i] << i;
    }
    return result;
}

void unpack(uchar cells[8], uchar x) {
    for (int i = 0; i < 8; i++) {
        cells[i] = (x >> i) & 1;
    }
}

uchar extract(int n, uchar x) {
    return (x >> n) & 1;
}

int sumGroup(int x_min, int x_max, uchar row[3]) {
    int sum;
    for (int j = 0; j < 3; j++) {
        for (int i = x_min; i < x_max; i++) {
            if (i != 1) sum += extract(i + x, row[j]);
        } 
    }
    return sum;
}

uchar sumNeighborsPrime(int x, int y, uchar lCol, uchar rCol, uchar row[3]) {
    int sum = 0;
    if (x == 1) {
        sum += sumGroup(1, 3, row);
        for (int i = 0; i < 3; i++) {
            sum += extract(y + j, lCol);
        }
    }
    
    else if (x == 6) {
        sum += sumGroup(0, 2, row);
        for (int i = 0; i < 3; i++) {
            sum += extract(y + j, rCol);
        }
    }

    else {
        sum = sumGroup(0, 3, row);
    }
    return sum;
}

//Iterate an array section
void iterate(uchar array[IMHT][(IMWD/noOfThreads)+2]) {
    const int ix = IMWD/noOfThreads;
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
        //printf("Waiting for Button Press...\n");
    	printf("Proceed with launch?\n");
    	fromButtons :> value;
    }
    
    toLEDs <: 1;

    passInitialState(c_in, fromWorker); 

    int closed = 0, confirm;
    bool iterating = true;
    printf("Terminate at will...\n");

    int ledPattern = 5;

    while (closed < noOfThreads) {
    	select {
    		case fromWorker[int i] :> confirm:
    			if (iterating) fromWorker[i] <: true;
    			else {
    				fromWorker[i] <: false;
    				closed++;
    			}

    			if (i == 0) {
    				toLEDs <: ledPattern;

    				if (ledPattern == 5) ledPattern = 1;
    				else ledPattern = 5;
    			}
    			break;
    		case fromButtons :> confirm:
    			if (confirm == 13) iterating = false;
    			break;	 
    	}
    }

    toLEDs <: 0;
    passOutputState(c_out, fromWorker);
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////

void DataOutStream(char outfname[], chanend c_in) {
  int res;
  uchar line[IMWD];

  //Open PGM file
  //printf("DataOutStream: Start...\n");
  res = _openoutpgm(outfname, IMWD, IMHT);
  if (res) {
    printf("DataOutStream: Error opening %s\n.", outfname);
    return;
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
  return;
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
    }
  }
}

void test() {
   assert(2+2==4); 
   assert(4-3==1);
   printf("Quick maths\n");
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
        on tile[1]: DataInStream("512x512.pgm", c_inIO);          //thread to read in a PGM image
        on tile[1]: DataOutStream("testout.pgm", c_outIO);       //thread to write out a PGM image
        on tile[1]: distributor(c_inIO, c_outIO, c_control, dist, c_buttons, c_leds);//thread to coordinate work on image

        on tile[0]: buttonListener(buttons, c_buttons);
        on tile[0]: showLEDs(leds, c_leds);
    
        on tile[0]: par (int i = 0; i < (noOfThreads/2); i++) {
            colWorker(i, dist[i], worker[i], worker[(i+1)%noOfThreads]);
        }

        on tile[1]: par (int i = 4; i < noOfThreads; i++) {
            colWorker(i, dist[i], worker[i], worker[(i+1)%noOfThreads]);
        }
    }

    return 0;
}
