/*
 * "Copyright (c) 2008 The Regents of the University  of California.
 * All rights reserved."
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 *
 * IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE UNIVERSITY OF
 * CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 *
 */

/*
 * Provides message dispatch based on the next header field of IP packets.
 *
 */
#include "IPDispatch.h"

configuration IPDispatchC {
  provides {
    interface SplitControl;
    interface IPAddress;
    interface IP[uint8_t nxt_hdr];

    interface Statistics<ip_statistics_t> as IPStats;
    interface Statistics<route_statistics_t> as RouteStats;
    interface Statistics<icmp_statistics_t> as ICMPStats;

  }
} implementation {
  
#ifndef SIM
  components CC2420ActiveMessageC as MessageC;
#else
  components ActiveMessageC as MessageC;
#endif
  components MainC, IPDispatchP, IPAddressC, IPRoutingP; 
  components NoLedsC as LedsC;
  components RandomC;

  SplitControl = IPDispatchP.SplitControl;
  IPAddress = IPAddressC;
  IP = IPDispatchP;

  IPDispatchP.Boot -> MainC;

#ifndef SIM
  IPDispatchP.IEEE154Send -> MessageC;
  IPDispatchP.IEEE154Receive -> MessageC;
#else
  IPDispatchP.IEEE154Send -> MessageC.AMSend[0];
  IPDispatchP.IEEE154Receive -> MessageC.Receive[0];
#endif
  IPDispatchP.Packet -> MessageC.SubAMPacket;
#ifdef LOW_POWER_LISTENING
  IPDispatchP.LowPowerListening -> MessageC;
#endif


  IPDispatchP.IEEE154Packet -> MessageC;
  IPDispatchP.PacketLink -> MessageC;
  IPDispatchP.CC2420Packet -> MessageC;

#ifdef DBG_TRACK_FLOWS
  IPDispatchP.getFlowID -> MessageC;
#endif


  IPDispatchP.Leds -> LedsC;

  IPDispatchP.IPAddress -> IPAddressC;

  components new TimerMilliC();
  IPDispatchP.ExpireTimer -> TimerMilliC;

  components new PoolC(message_t, IP_NUMBER_FRAGMENTS) as FragPool;

  components new PoolC(send_entry_t, IP_NUMBER_FRAGMENTS) as SendEntryPool;
  components new QueueC(send_entry_t *, IP_NUMBER_FRAGMENTS);

  components new PoolC(send_info_t, N_FORWARD_ENT) as SendInfoPool;

  IPDispatchP.FragPool -> FragPool;
  IPDispatchP.SendEntryPool -> SendEntryPool;
  IPDispatchP.SendInfoPool  -> SendInfoPool;
  IPDispatchP.SendQueue -> QueueC;

  components ICMPResponderC;
  components new TimerMilliC() as TGenTimer;
  IPDispatchP.ICMP -> ICMPResponderC;
  IPRoutingP.ICMP  -> ICMPResponderC;
  IPDispatchP.RadioControl -> MessageC;

  IPDispatchP.IPRouting -> IPRoutingP;
  IPRoutingP.Boot -> MainC;
  IPRoutingP.Leds -> LedsC;
  IPRoutingP.IPAddress -> IPAddressC;
  IPRoutingP.Random -> RandomC;
  IPRoutingP.TrafficGenTimer -> TGenTimer;
  IPRoutingP.TGenSend -> IPDispatchP.IP[NXTHDR_UNKNOWN];

  IPStats    = IPDispatchP;
  RouteStats = IPRoutingP;
  ICMPStats  = ICMPResponderC;

  components new TimerMilliC() as RouteTimer;
  IPRoutingP.SortTimer -> RouteTimer;

#ifdef DELUGE
  components NWProgC;
#endif

}
