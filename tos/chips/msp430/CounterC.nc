//$Id$

/* "Copyright (c) 2000-2003 The Regents of the University of California.  
 * All rights reserved.
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement
 * is hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 * 
 * IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE UNIVERSITY
 * OF CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 */

//@author Cory Sharp <cssharp@eecs.berkeley.edu>

// The TinyOS Timer interfaces are discussed in TEP 102.

configuration CounterC
{
  provides interface Counter32<TMilli> as Counter32Milli;
  provides interface Counter<uint32_t,TMilli> as CounterMilli;
  provides interface Counter<uint16_t,TMilli> as MSP430CounterMilli;
}
implementation
{
  components MSP430TimerC
           , new MSP430CounterM(TMilli) as MSP430CounterB
	   , new WidenCounterM(uint32_t,uint16_t,uint16_t,TMilli) as WidenB
	   , new CastCounter32(TMilli) as CastB
	   ;
  
  Counter32Milli = CastB.Counter;
  CounterMilli = WidenB.Counter;
  MSP430CounterMilli = MSP430CounterB.Counter;

  CastB.CounterFrom -> WidenB.Counter;
  WidenB.CounterFrom -> MSP430CounterB.Counter;
  MSP430CounterB.MSP430Timer -> MSP430TimerC.TimerB;
}

