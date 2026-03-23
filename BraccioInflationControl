// look into deflation if too high for braccio, or inflate if dips below pressure


// IMPORT LIBRARIES
// #include <Wire.h>
#include "Adafruit_MPRLS.h"  // Pressure sensor
#include <LiquidCrystal.h>   // LCD display


// PRESSSURE SENSOR SETUP
#define RESET_PIN -1                                      // Reset pin (not used, set to -1)
#define EOC_PIN -1                                        // End-of-conversion pin (not used, set to -1)
Adafruit_MPRLS mpr = Adafruit_MPRLS(RESET_PIN, EOC_PIN);  // Create sensor object

// LCD SETUP
LiquidCrystal lcd(8, 9, 6, 5, 4, 2);  // Initialize pins of lcd screen

// VARIABLES
// PIN ASSIGNMENTS
const int buttonPin = 7;  // Button to start inflation
const int directionPin = 12;
const int pwmPin = 3;
const int otherArduinoPinWrite = 10;
const int otherArduinoPinRead = 11;
const int valvePin = 13;

//  Pressure variables
const float targetPressure = 22.0;    // Target pressure in kPa
const float tolerancePressure = 0.1;  // Allowable tolerance ±0.5 kPa (NOT USED YET)
float measuredPressure = 0.0;         // Measured pressure (kPa)
float sumInitialPressure = 0.0;       // Sum of measured pressure in setup() (hPa)
float offsetPressure = 0.0;           // Offset pressure based off measured pressure in setup() (kPa)

float increase = 1.0;
int pwmMotor = increase * 255;
int timeStart = 0;  // start of inflation

// Inflation variables
bool lastButtonState = 1;  // To track if button pressed in last iteration
bool buttonState = 0;      // To track if button is pressed
float lastPressure = 0.0;  // Float first value of previous pressure for LCD

bool operate = 1;

void setup() {
  // SERIAL OUTPUT SETUP
  Serial.begin(115200);  // baud rate



  // PINMODE ASSIGNEMNT
  pinMode(otherArduinoPinRead, INPUT_PULLUP);
  pinMode(otherArduinoPinWrite, OUTPUT);
  digitalWrite(otherArduinoPinWrite, 1);  // PULLUP
  pinMode(buttonPin, INPUT_PULLUP);       // Button to start inflation, pullup to prevent floating pin
  pinMode(pwmPin, OUTPUT);
  pinMode(directionPin, OUTPUT);  // motor direction
  pinMode(valvePin, OUTPUT);
  digitalWrite(directionPin, 0);

  // INITIALIZE PRESSURE SENSOR
  Serial.println("Looking for presure sensor...");
  if (!mpr.begin()) {  // If pressure sensor not found/working
    Serial.println("Failed to communicate with MPRLS sensor, check wiring?");
    while (1) {  // freeze program forever
      delay(10);
    }
  }
  Serial.println("Found MPRLS sensor");

  // CALIBRATE PRESSURE SENSOR TO P_ATM
  Serial.println("Calibrating pressure...");
  for (int i = 1; i <= 10; i++) {              // loop 10 times
    sumInitialPressure += mpr.readPressure();  // read and sum pressure readings (hPa)
    delay(100);                                // delay 100 ms
  }
  Serial.println("Calibration complete.");
  offsetPressure = sumInitialPressure / 10.0;  // sum divided by number of readings (hPa)
  Serial.print("Offset pressure (kPa): ");
  Serial.println(offsetPressure / 10.0);  // converted to kPa for LCD

  // INITIALIZE LCD
  lcd.begin(16, 2);  // Power on LCD screen
  lcd.print("Ready");

  Serial.println("Ready");
  delay(1000);  // delay 1000 ms
}




void loop() {
  // check if button pressed
  buttonState = digitalRead(buttonPin);  // pullup (1 = not pressed, 0 = pressed)

  // tell other
  if (buttonState == 0) {
    digitalWrite(otherArduinoPinWrite, 0);  // PULLUP
    delay(1000);
    digitalWrite(otherArduinoPinWrite, 1);  // PULLUP
    delay(10);
    Serial.println("Operate");
    // wait for inflation instruction
    // inflate
    // tell other inflated
    Inflate();

    // wait for deflation
    // deflate
    // tell other deflated

    // end
  }
  increase = 0.75;
  pwmMotor = increase * 255;

  delay(50);  // delay 50 ms
}




void Inflate() {
  bool loopCheck = 1;
  bool inflateSignal = 1;
  bool loopInflate = 1;
  bool loopHold = 1;
  bool loopDeflate = 1;

  // Wait for inflate signal
  while (loopCheck == 1) {
    inflateSignal = digitalRead(otherArduinoPinRead);
    Serial.println("Check Inflate");
    // Inflate
    if (inflateSignal == 0) {  // PULLUP
      digitalWrite(valvePin, 1);
      Serial.println("Inflate");
      while (loopInflate == 1) {
        // Read pressure from sensor and print
        measuredPressure = Measure_then_print();
        // if (measuredPressure - lastPressure < 2.0) {
        //   increase = increase + 0.05;
        //   pwmMotor = increase * 255;
        //   if (pwmMotor > 255) {
        //     pwmMotor = 255;
        //   }
        // }
        // Serial.print("Increase: ");
        // Serial.println(increase);
        // lastPressure = measuredPressure;  // set new measured pressure value

        // if measured less than target, motor on for 500 ms
        if ((targetPressure - measuredPressure) > tolerancePressure) {
          Pump(targetPressure, measuredPressure, tolerancePressure, pwmMotor);
        } else {
          // motor off
          analogWrite(pwmPin, 0);

          // tell other done
          digitalWrite(otherArduinoPinWrite, 0);  // PULLUP
          delay(500);
          digitalWrite(otherArduinoPinWrite, 1);  // PULLUP
          delay(50);

          inflateSignal = 1;
          loopInflate = 0;
          loopCheck = 0;
        }
        delay(10);
      }
    }
    delay(10);
  }

  // Hold Pressure
  while (loopHold == 1) {

    // Read pressure from sensor and print
    measuredPressure = Measure_then_print();

    // if measured less than target, motor on
    Pump(targetPressure, measuredPressure, tolerancePressure, pwmMotor);

    loopDeflate = digitalRead(otherArduinoPinRead);
    if (loopDeflate == 0) {
      loopHold = 0;
    }
    delay(10);
  }

  // Deflate
  analogWrite(pwmPin, 0);
  while (loopDeflate == 0) {
    digitalWrite(valvePin, 0);
    measuredPressure = Measure_then_print();  // Subract offset and convert to kPa
    if (measuredPressure < tolerancePressure) {
      loopDeflate = 1;

      // tell other done
      digitalWrite(otherArduinoPinWrite, 0);  // PULLUP
      delay(500);
      digitalWrite(otherArduinoPinWrite, 1);  // PULLUP
      delay(50);
    }
    delay(10);
  }
}

float Measure_then_print() {
  measuredPressure = (mpr.readPressure() - offsetPressure) / 10.0;  // Subract offset and convert to kPa
  Serial.print("  Time: ");
  Serial.print(millis() - timeStart);
  Serial.print("   Measured: ");
  Serial.println(measuredPressure, 2);  // to 2 decimal places
                                        // if pressure changed from last iteration by >0.02 -> noise floor of sensor
  lcd.setCursor(0, 1);                  // bottom line
  lcd.print("Measured: ");
  lcd.print(measuredPressure, 2);  // to 2 decimal places

  return measuredPressure;
}


void Pump(int targetPressure, int measuredPressure, int tolerancePressure, int pwmMotor) {
  if ((targetPressure - measuredPressure) > tolerancePressure) {
    analogWrite(pwmPin, pwmMotor);
    delay(100);
    analogWrite(pwmPin, 0);
    delay(50);
  } else {  // motor off
    analogWrite(pwmPin, 0);
  }
}
