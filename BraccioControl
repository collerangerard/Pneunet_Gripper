/*
  testBraccio90.ino

 testBraccio90 is a setup sketch to check the alignment of all the servo motors
 This is the first sketch you need to run on Braccio
 When you start this sketch Braccio will be positioned perpendicular to the base
 If you can't see the Braccio in this exact position you need to reallign the servo motors position

 Created on 18 Nov 2015
 by Andrea Martino

 This example is in the public domain.
 */

#include <Braccio.h>
#include <Servo.h>

// Pin setup
const int mainArduinoPinWrite = 2;
const int mainArduinoPinRead = 4;

bool operate = 1; // PULLUP SO OPPOSITE

// Start position
const int start_M1 = 0;
const int start_M2 = 40;
const int start_M3 = 180;
const int start_M4 = 0;
const int start_M5 = 180;
const int start_M6 = 73;

// Grab position
// const int grab_M1 = 30;
// const int grab_M2 = 0;
// const int grab_M3 = 62;
// const int grab_M4 = 12;
// const int grab_M5 = start_M5;
// const int grab_M6 = start_M6;
const int grab_M1 = 30;
const int grab_M2 = 23;
const int grab_M3 = 70;
const int grab_M4 = 0;
const int grab_M5 = 140;
const int grab_M6 = start_M6;

// Lift position
const int lift_M1 = 80;
const int lift_M2 = 40;
const int lift_M3 = 80;
const int lift_M4 = grab_M4;
const int lift_M5 = grab_M5;
const int lift_M6 = grab_M6;

// Release position
const int release_M1 = lift_M1;
const int release_M2 = 25;
const int release_M3 = 80;
const int release_M4 = lift_M4;
const int release_M5 = lift_M5;
const int release_M6 = lift_M6;

Servo base;
Servo shoulder;
Servo elbow;
Servo wrist_rot;
Servo wrist_ver;
Servo gripper;

const int time = 500;  // delay in ms
const int speed = 20;  // speed of steps


void setup() {
    // SERIAL OUTPUT SETUP
  Serial.begin(115200);  // baud rate

  // PINMODE ASSIGNMENT
  pinMode(mainArduinoPinRead, INPUT_PULLUP);
  pinMode(mainArduinoPinWrite, OUTPUT);
  digitalWrite(mainArduinoPinWrite, 1); // PULLUP
  //Initialization functions and set up the initial position for Braccio
  //All the servo motors will be positioned in the "safety" position:
  //Base (M1):90 degrees
  //Shoulder (M2): 45 degrees
  //Elbow (M3): 180 degrees
  //Wrist vertical (M4): 180 degrees
  //Wrist rotation (M5): 90 degrees
  //gripper (M6): 10 degrees
  Braccio.begin();
  //  starting positionBraccio.ServoMovement(30,         0, 40, 180, 0, 180,  73);
}

void loop() {
  /*
   Step Delay: a milliseconds delay between the movement of each servo.  Allowed values from 10 to 30 msec.
   M1=base degrees. Allowed values from 0 to 180 degrees
   M2=shoulder degrees. Allowed values from 15 to 165 degrees
   M3=elbow degrees. Allowed values from 0 to 180 degrees
   M4=wrist vertical degrees. Allowed values from 0 to 180 degrees
   M5=wrist rotation degrees. Allowed values from 0 to 180 degrees
   M6=gripper degrees. Allowed values from 10 to 73 degrees. 10: the toungue is open, 73: the gripper is closed.
  */
  operate = digitalRead(mainArduinoPinRead);
  Serial.print("Operate: ");
    Serial.println(operate);
  if (operate == 0) {
    delay(1000);
    // Grab
    Braccio.ServoMovement(speed, grab_M1, start_M2, start_M3, grab_M4, grab_M5, start_M6);  // M1 & M4
    delay(time);
    Braccio.ServoMovement(speed, grab_M1, start_M2, grab_M3, grab_M4, grab_M5, start_M6);  // M1 & M4
    delay(time);
    Braccio.ServoMovement(speed, grab_M1, start_M2, grab_M3, grab_M4, grab_M5, start_M6);  // M3
    delay(time);
    Braccio.ServoMovement(speed, grab_M1, grab_M2, grab_M3, grab_M4, grab_M5, start_M6);  // M3
    delay(time);
    grab();

    // Lift
    Braccio.ServoMovement(speed, grab_M1, lift_M2, lift_M3, grab_M4, grab_M5, grab_M6);  // M2 & M3
    delay(time);
    Braccio.ServoMovement(speed, lift_M1, lift_M2, lift_M3, grab_M4, grab_M5, grab_M6);  // M1
    delay(time);

    // Release
    Braccio.ServoMovement(speed, lift_M1, release_M2, lift_M3, lift_M4, lift_M5, lift_M6);  // M2
    delay(time);
    Braccio.ServoMovement(speed, lift_M1, release_M2, release_M3, lift_M4, lift_M5, lift_M6);  // M3
    delay(time);
    release();

    // End = Start
    Braccio.ServoMovement(speed, release_M1, release_M2, release_M3, release_M4, release_M5, release_M6);  // M2
    delay(time);
    Braccio.ServoMovement(speed, release_M1, release_M2, start_M3, release_M4, release_M5, release_M6);  // M2
    delay(time);
    Braccio.ServoMovement(speed, release_M1, start_M2, start_M3, release_M4, release_M5, release_M6);  // M2
    delay(time);
    Braccio.ServoMovement(speed, start_M1, start_M2, start_M3, release_M4, release_M5, release_M6);  // M2
    delay(time);
    Braccio.ServoMovement(speed, start_M1, start_M2, start_M3, start_M4, start_M5, start_M6);
    delay(time);
    delay(1000);
  }
  delay(10);
}

void grab() {

    Serial.println("Grab");
  bool inflated = 1; // PULLUP

  // send message to main that in position
  digitalWrite(mainArduinoPinWrite, 0); // PULLUP

  // wait for response, exit
  while (inflated == 1) { // PULLUP
    inflated = digitalRead(mainArduinoPinRead); // PULLUP
    delay(100);
  }

  // stop telling main that in position
  digitalWrite(mainArduinoPinWrite, 1); // PULLUP
  
    Serial.println("Grab done");
}

void release() {
  
    Serial.println("Release");
  bool released = 1; // PULLUP

  // send message to main that in position
  digitalWrite(mainArduinoPinWrite, 0); // PULLUP

  // wait for response, exit
  while (released == 1) {
    released = digitalRead(mainArduinoPinRead); // PULLUP
    delay(100);
  }

  // stop telling main that in position
  digitalWrite(mainArduinoPinWrite,1);
      Serial.println("Release done");
}
