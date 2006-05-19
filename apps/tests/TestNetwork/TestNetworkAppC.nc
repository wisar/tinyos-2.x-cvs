/**
 * TestNetworkC exercises the basic networking layers, collection and
 * dissemination. The application samples DemoSensorC at a basic rate
 * and sends packets up a collection tree. The rate is configurable
 * through dissemination.
 *
 * See TEP118: Dissemination and TEP 119: Collection for details.
 * 
 * @author Philip Levis
 * @version $Revision$ $Date$
 */

configuration TestNetworkAppC {}
implementation {
  components TestNetworkC, MainC, LedsC, ActiveMessageC;
  components new DisseminatorC(uint16_t, 0x1) as Object16C;
  components new CollectionSenderC(0);
  components new TimerMilliC();
  components new DemoSensorC();

  TestNetworkC.Boot -> MainC;
  TestDisseminationC.Leds -> LedsC;
  TestDisseminationC.Timer -> TimerMilliC;
  TestDisseminationC.RadioControl -> ActiveMessageC;
  TestDisseminationC.DisseminationPeriod -> Object16C;
  TestDisseminationC.Send -> CollectionSenderC;
}

