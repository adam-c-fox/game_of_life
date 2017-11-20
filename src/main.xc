// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include <assert.h>

#define  IMHT 64                  //image height
#define  IMWD 64                  //image width
#define  noOfThreads 4
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
  printf("DataInStream: Start...\n");

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
  printf("DataInStream: Done...\n");
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////

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

void colWorker(int id, chanend dist_in, chanend c_left, chanend c_right) {
  int colwidth = (IMWD/noOfThreads);
  uchar grid[IMHT][(IMWD/noOfThreads)+2];

  //Read in corresponding segment of world
  for (int y = 0; y<IMHT; y++) {
    for (int x = 1; x <= colwidth; x++){
      dist_in :> grid[y][x];
    }
  } 

  bool iterating = true;

  //Iterate
  while (iterating) {
    //If even column: pass to right, then read from left
    //If odd column : read from left, then pass to right
    if ((id % 2) == 0) {
      for (int y = 0; y<IMHT; y++) {
        c_right <: grid[y][colwidth];
        c_left  :> grid[y][0];

        c_right :> grid[y][colwidth+1];
        c_left  <: grid[y][1];
      }
    }
    else {
      for (int y = 0; y<IMHT; y++) {
        c_left :> grid[y][0];
        c_right <: grid[y][colwidth];

        c_left  <: grid[y][1];
        c_right :> grid[y][colwidth+1];
      }
    } 

    iterate(grid);

    dist_in <: 1;
    dist_in :> iterating;


  }

  int proceed;
  dist_in :> proceed;
    
  //Send out
  for (int y = 0; y<IMHT; y++) {
    for (int x = 1; x <= colwidth; x++){
      //printf("hello: %d\n", id);
      dist_in <: grid[y][x];

    }
  }  
}


void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend fromWorker[noOfThreads], chanend fromButtons, chanend toLEDs) {
  //Starting up and wait for  tilting of the xCore-200 Explorer
  printf("ProcessImage: Start, size = %dx%d\n", IMHT, IMWD);

  int value = 0;

  while (value != 14) {
  	//printf("Waiting for Button Press...\n");
  	printf("Confirm launch...\n");
  	fromButtons :> value;
  }
  
  toLEDs <: 1;

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  printf("Reading in image...\n");

  //uchar grid[IMHT][IMWD];
  uchar temp;

	  for (int y = 0; y < IMHT; y++) {   //go through all lines
	    for (int n = 0; n < noOfThreads; n++) {
	      for (int x = 0; x < (IMWD/noOfThreads); x++) { //go through each pixel per line
	        c_in :> temp;
	        fromWorker[n] <: temp;                    //read the pixel value

	        //c_out <: (uchar)(val ^ 0xFF); //send some modified pixel out
	      }
	    }
	  }


  printf("Image read in successfully.\n");

  int closed = 0, confirm;
  bool iterating = true;
  printf("Waiting for second button press...\n");

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
  printf("Button press confirmed, saving image...\n");

  for (int i = 0; i<noOfThreads; i++) {
  	fromWorker[i] <: 1;
  }

  for (int y = 0; y < IMHT; y++) {   //go through all lines
    for (int n = 0; n < noOfThreads; n++) {
      for (int x = 0; x < (IMWD/noOfThreads); x++) { //go through each pixel per line
        fromWorker[n] :> temp;                    //read the pixel value

        c_out <: temp;
      }
    }
  }


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
  printf("DataOutStream: Start...\n");
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
        on tile[0]: DataInStream("64x64.pgm", c_inIO);          //thread to read in a PGM image
        on tile[0]: DataOutStream("testout.pgm", c_outIO);       //thread to write out a PGM image
        on tile[0]: distributor(c_inIO, c_outIO, c_control, dist, c_buttons, c_leds);//thread to coordinate work on image

        on tile[0]: buttonListener(buttons, c_buttons);
        on tile[0]: showLEDs(leds, c_leds);

    
        on tile[1]: par (int i = 0; i < noOfThreads; i++) {
            colWorker(i, dist[i], worker[i], worker[(i+1)%noOfThreads]);
        }
    }

    return 0;
}
