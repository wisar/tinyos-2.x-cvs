//$Id$
// @author Cory Sharp <cssharp@eecs.berkeley.edu>

interface TimerJiffyAsync
{
  async command error_t setOneShot( uint32_t jiffy );

  async command error_t stop();

  async command bool isSet();

  async event error_t fired();
}

