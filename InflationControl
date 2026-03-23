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
int directionPin = 12;
int pwmPin = 3;

//  Pressure variables
const float targetPressure = 20.0;    // Target pressure in kPa
const float tolerancePressure = 0.1;  // Allowable tolerance ±0.5 kPa (NOT USED YET)
float measuredPressure = 0.0;         // Measured pressure (kPa)
float sumInitialPressure = 0.0;       // Sum of measured pressure in setup() (hPa)
float offsetPressure = 0.0;           // Offset pressure based off measured pressure in setup() (kPa)

float increase = 0.35;
int pwmMotor = increase * 255;
int timeStart = 0;  // start of inflation

// Inflation variables
bool inflate = 0;          // Boolean to start pump motor, set by button
bool lastButtonState = 1;  // To track if button pressed in last iteration
bool buttonState = 0;      // To track if button is pressed
float lastPressure = 0.0;  // Float first value of previous pressure for LCD

void setup() {
  // SERIAL OUTPUT SETUP
  Serial.begin(115200);  // baud rate



  // PINMODE ASSIGNEMNT

  pinMode(buttonPin, INPUT_PULLUP);  // Button to start inflation, pullup to prevent floating pin
  pinMode(pwmPin, OUTPUT);
  pinMode(directionPin, OUTPUT);  // motor direction
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
  // Check if button pressed
  buttonState = digitalRead(buttonPin);  // pullup (1 = not pressed, 0 = pressed)

  // if button just pressed (falling edge)
  if (lastButtonState == 1 && buttonState == 0) {
    inflate = 1;          // inflate pneunet
                          // LCD screen
    lcd.setCursor(0, 0);  // top line
    lcd.print("Target: ");
    lcd.print(targetPressure, 2);  // to 2 decimal places
    Serial.print("Target: ");
    Serial.println(targetPressure, 2);  // to 2 decimal places
    timeStart = millis();
  }
  lastButtonState = buttonState;  // set to new button state

  if (inflate) {
    // Read pressure from sensor

    measuredPressure = (mpr.readPressure() - offsetPressure) / 10.0;  // Subract offset and convert to kPa
    Serial.print("  Time: ");
    Serial.print(millis() - timeStart);
    Serial.print("   Measured: ");
    Serial.println(measuredPressure, 2);  // to 2 decimal places
                                          // if pressure changed from last iteration by >0.02 -> noise floor of sensor
    lcd.setCursor(0, 1);                  // bottom line
    lcd.print("Measured: ");
    lcd.print(measuredPressure, 2);  // to 2 decimal places
    if (measuredPressure - lastPressure < 2.0) {
      increase = increase+0.05;
      pwmMotor = increase*255;
      if (pwmMotor > 255) {
        pwmMotor = 255;
      }
    }
    lastPressure = measuredPressure;  // set new measured pressure value

    // if measured less than target, motor on for 500 ms
    if ((targetPressure - measuredPressure) > tolerancePressure) {
      analogWrite(pwmPin, pwmMotor);
      digitalWrite(directionPin, 0);
      delay(1000);
      analogWrite(pwmPin, 0);
      delay(1000);
    } else {  // motor off
      analogWrite(pwmPin, 0);
      inflate = 0;
    }
  }

  delay(50);  // delay 50 ms
}
