// $Id$

configuration BlinkC
{
}
implementation
{
  components Main, BlinkM, LedsC, new AlarmMilliC() as AlarmC;
  BlinkM.Boot -> Main;
  Main.SoftwareInit -> LedsC;
  Main.SoftwareInit -> AlarmC;
  BlinkM.Leds -> LedsC;
  BlinkM.Alarm -> AlarmC;
}

