/*
 * Copyright (c) 2004-2006, Technische Universitaet Berlin
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without 
 * modification, are permitted provided that the following conditions 
 * are met:
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright 
 *   notice, this list of conditions and the following disclaimer in the 
 *   documentation and/or other materials provided with the distribution.
 * - Neither the name of the Technische Universitaet Berlin nor the names 
 *   of its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT 
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, 
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, 
 * OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY 
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE 
 * USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * - Description ---------------------------------------------------------
 *  Preamble Sample LinkLayerControl
 * - Revision -------------------------------------------------------------
 * $Revision$
 * $Date$
 * @author: Kevin Klues (klues@tkn.tu-berlin.de)
 * @author: Philipp Huppertz (huppertz@tkn.tu-berlin.de)
 * ========================================================================
 */

configuration LinkLayerControlC {
   provides {
     interface Init;
     interface SplitControl;
     interface Send;
     interface Receive;
     interface PacketAcknowledgements;
   }
   uses {
     interface SplitControl as MacSplitControl;
     interface SplitControl as RadioSplitControl;
     interface Send as SendDown;
     interface Receive as ReceiveLower;        
   }
}
implementation
{
  components LinkLayerControlP as Llc;
  
    Init = Llc;
    SplitControl = Llc;
    MacSplitControl =  Llc.MacSplitControl;
    RadioSplitControl =  Llc.RadioSplitControl;
    Send = Llc.Send;
    Receive = Llc.Receive;
    PacketAcknowledgements = Llc;    
    ReceiveLower = Llc.ReceiveLower;
    SendDown = Llc.SendDown;
}