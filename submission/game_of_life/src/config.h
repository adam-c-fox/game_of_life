/*
/   This module contains settings for the run configuration of the program
/     
/   The program must be remade (with xmake) every time a setting is changed
/
*/ 

#define  IMHT 64                //image height
#define  IMWD 64                //image width

#define  INPUT "64x64.pgm"
#define  OUTPUT "testout"       //Outputs will be in the form testout_n where n is the iteration number

#if ((IMHT%8 != 0) || (IMHT != IMWD)) 
  #error "Image not allowed."
#endif

#define  noOfThreads 2			//Our implementation requires that this must be 2^n
#define  debugMode 0                    //Run tests and not wait for button input, increases memory usage
#define  generateOnBoard 0		//If true, will ignore input name
#define  printAllImages 0               //Outputs every iteration image


