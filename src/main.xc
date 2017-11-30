/*
/  Adam Beddoe and Adam Fox's concurrent implementation of the Game of Life
/       Config file (config.h) specifies image size and settings
/
*/

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include <assert.h>
#include <string.h>
#include "packedChunkWorker.h"
#include "unpackedWorker.h"
#include "utility.h"
#include "config.h"


/////////////////////////////////////////////////////////////////////////////////////////
//
// LEDs, accelerometer and buttons
//
/////////////////////////////////////////////////////////////////////////////////////////

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

//Displays an LED pattern
int showLEDs(out port p, chanend fromDistributor) {
    int pattern; //1st bit...separate green LED
                 //2nd bit...blue LED
                 //3rd bit...green LED
                 //4th bit...red LED
    while (1) {
         fromDistributor :> pattern;   //receive new pattern
        p <: pattern;                  //send pattern to LED port
    }
    return 0;
}

//Bit packs instructions for LED colours
int led(int red, int green, int blue, int greenSeperate) {
    int result = 0;

    uchar buffer[8] = {0, 0, 0, 0, red, green, blue, greenSeperate};
    result = pack(buffer);
    return result;
}

//Read buttons and send button pattern to userAnt
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

// Initialise and  read orientation, send first tilt event to channel
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

        if (tilted) {
            if (x<30) {
                tilted = 1 - tilted;
                toDist <: 0;
            }
        }

    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// File IO functions. 
//
/////////////////////////////////////////////////////////////////////////////////////////

//Write pixel stream from channel c_in to PGM image file
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
    	}
  
  	//Close the PGM image
    	_closeoutpgm();
    	printf("Image saved.\n");
    	count++;
    }
}


//Read Image from PGM file from path infname[] to channel c_out
void DataInStream(char infname[], chanend c_out) {
    int res;
    uchar line[IMWD], temp;
  
    if (!generateOnBoard) {
        res = _openinpgm(infname, IMWD, IMHT);
        if (res) {
            printf("DataInStream: Error opening %s\n.", infname);
            return;
        }
  
        for (int y = 0; y < IMHT; y++) {
            _readinline(line, IMWD);
            for (int x = 0; x < IMWD; x++) {
                c_out <: line[x];
            }
        }
    }
    else {
        for (int y = 0; y < IMHT; y++) {
            for (int x = 0; x < IMWD; x++) {
                temp = rand()%2;
                c_out <: temp;
            }
        }
    }
  
    //Read image line-by-line and send byte by byte to channel c_out
    for (int y = 0; y < IMHT; y++) {
        _readinline(line, IMWD);
        for (int x = 0; x < IMWD; x++) {
            c_out <: line[x];
            temp = rand()%2;
            c_out <: temp;
        }
    }
  
    _closeinpgm();
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

//Prints the status report for the paued board
void statusReport(int rounds, int liveCells, double timeElapsedFloat) {
    printf("\n-------< STATUS REPORT >-------\n");
    printf("Rounds processed:        %d\n", rounds);
    printf("Live cells:              %d\n", liveCells);
    printf("Processing time elapsed: %lf\n", timeElapsedFloat/100000000);
    printf("-------------------------------\n\n");
}

//Adds the live thread count from all workers
int sum(int threadCells[noOfThreads]) {
    int sum = 0;
    for (int i = 0; i < noOfThreads; i++) {
        sum += threadCells[i];
    }
    return sum;
}

//Waits for button input
void buttonInput(chanend fromButtons) {
    int buttonInput = 0;
    while (buttonInput != 14 && !debugMode) {
       	printf("Proceed with launch?\n");
    	fromButtons :> buttonInput;
    }
}

//Sends an int to all workers
void sendAll(int n, chanend fromWorker[noOfThreads]) {
    for (int i = 0; i<noOfThreads; i++) {
        fromWorker[i] <: 0;
    }
}

//Controls data flow between all threads
void distributor(chanend c_in, chanend c_out, chanend fromAcc, chanend fromWorker[noOfThreads], chanend fromButtons, chanend toLEDs) {
    printf("ProcessImage: Start, size = %dx%d\n", IMHT, IMWD);

    buttonInput(fromButtons); 
    
    toLEDs <: led(0, 0, 0, 1);

    passInitialState(c_in, fromWorker); 

    int closed = 0, rounds = 0, confirm = 0, ledPattern = led(0, 1, 0, 1);
    int threadCells[noOfThreads];
    bool iterating = true, reporting = false;
    timer t;
    uint32_t startTime, endTime, timeElapsed = 0, prevTime, timeCheck, timeElapsedTemp;
    double timeElapsedFloat = 0;

    printf("Terminate at will...\n");

    t :> startTime;
    timeCheck = startTime;

    while (1) {
    	while (closed < noOfThreads) {  
	    select {
                case fromAcc :> confirm:
                    if (confirm == 1) {
                        iterating = false;
                        reporting = true;
                    }
                    break;

	        case fromWorker[int i] :> confirm:
	            if (iterating && !printAllImages) fromWorker[i] <: true;
                    else {
	                fromWorker[i] <: false;
                    fromWorker[i] :> threadCells[i];
	                closed++;
	            }

	            if (i == 0) {
                        toLEDs <: ledPattern;
                        rounds++;

                        prevTime = timeCheck;
                        t :> timeCheck;
                        if (timeCheck < prevTime) {
                            timeElapsedTemp = prevTime-startTime;
                            timeElapsedFloat += timeElapsedTemp;

                            t :> startTime;
                        }


                        if (rounds == 100) {
                            t :> endTime;

                            timeElapsed += endTime-startTime;
                            timeElapsedFloat += timeElapsed;

                            printf("100 round time: %lf\n", timeElapsedFloat/100000000);
                        }

                        ledPattern = (ledPattern == led(0, 1, 0, 1)) ? led(0, 0, 0, 0) : led(0, 1, 0, 1);
	            }
	            break;

	        case fromButtons :> confirm:
	            if (confirm == 13) iterating = false;	
	            break;	
	        }
            }

            t :> endTime;


            if (reporting) {
                reporting = false;
                
                toLEDs <: led(1, 0, 0, 0); //Red LED when paused
                
                timeElapsed += endTime-startTime;
                timeElapsedFloat = timeElapsed;
                int liveCells = sum(threadCells);

                statusReport(rounds, liveCells, timeElapsedFloat);

                fromAcc :> int continueSignal;

                sendAll(0, fromWorker);
            }
            else {
                timeElapsed += endTime-startTime;

                toLEDs <: led(0, 0, 1, 0); //Blue LED when exporting image
                passOutputState(c_out, fromWorker);
                toLEDs <: led(0, 0, 0, 0);          
                
            }

            t :> startTime;
            iterating = true;
            closed = 0;
            
    }
}

//Selects appropriate worker based on image size
void worker(int id, chanend dist_in, chanend c_left, chanend c_right) {
    if (IMHT <= 256 || IMWD <= 256) unpackedWorker(id, dist_in, c_left, c_right);
    else packedChunkWorker(id, dist_in, c_left, c_right);
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Main and testing
//
/////////////////////////////////////////////////////////////////////////////////////////

//Runs unit tests for all modules
void test() {
    testPackedChunkWorker();
    testUtility();
    printf("All tests pass!\n");
}

//Orchestrate concurrent system and start up all threads
int main(void) {
    i2c_master_if i2c[1];               
    chan c_inIO, c_outIO, c_control;
    chan c_buttons, c_leds;

    chan workerChan[noOfThreads], dist[noOfThreads];
    
    par {
        on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);
        on tile[0]: orientation(i2c[0],c_control);      
        on tile[1]: DataInStream(INPUT, c_inIO);       
        on tile[0]: DataOutStream(OUTPUT, c_outIO);   
        on tile[1]: distributor(c_inIO, c_outIO, c_control, dist, c_buttons, c_leds);

        on tile[0]: if (debugMode) test();

        on tile[0]: buttonListener(buttons, c_buttons);
        on tile[0]: showLEDs(leds, c_leds);
    
        on tile[0]: par (int i = 0; i < (noOfThreads/2); i++) {
            worker(i, dist[i], workerChan[i], workerChan[(i+1)%noOfThreads]);
        }

        on tile[1]: par (int i = (noOfThreads/2); i < noOfThreads; i++) {
            worker(i, dist[i], workerChan[i], workerChan[(i+1)%noOfThreads]);
        }

    }

    return 0;
}
