// $Id$

configuration BlinkC
{
}
implementation
{
  components MainC, BlinkM, LedsC, new AlarmMilliC() as AlarmC;
  BlinkM.Boot -> MainC;
  MainC.SoftwareInit -> LedsC;
  MainC.SoftwareInit -> AlarmC;
  BlinkM.Leds -> LedsC;
  BlinkM.Alarm -> AlarmC;
}

