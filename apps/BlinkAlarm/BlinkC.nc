// $Id$

configuration BlinkC
{
}
implementation
{
  components Main, BlinkM, LedsC, AlarmC;
  BlinkM.Boot -> Main;
  Main.SoftwareInit -> LedsC;
  Main.SoftwareInit -> AlarmC;
  BlinkM.Leds -> LedsC;
  BlinkM.Alarm -> AlarmC.AlarmTimer32khz;
}

