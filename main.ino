#include <LiquidCrystal.h>

LiquidCrystal lcd(12, 11, 5, 4, 3, 2);

volatile int pulseCount;
const byte pinSensor = 0;
float flowRate;
unsigned long timeDelta;
unsigned long oldTime;
unsigned long currentTime;

void setup()
{
  pinMode(39, INPUT);
  digitalWrite(2, HIGH);
  lcd.begin(16, 2);
  lcd.print("Sensor de flujo");
  attachInterrupt(pinSensor, pulseCounter, FALLING);
  oldTime = millis();
}

void loop()
{
  currentTime = millis();
  timeDelta = (currentTime - oldTime);
  if (timeDelta > 1000)
  {
    oldTime = currentTime;
    flowRate = pulseCount / 7.5; // L/min
    pulseCount = 0;
    lcd.setCursor(0, 1);
    lcd.print("Flujo: ");
    lcd.print(flowRate);
    lcd.print(" L/min");
  }


}

void pulseCounter()
{
  pulseCount++;
}