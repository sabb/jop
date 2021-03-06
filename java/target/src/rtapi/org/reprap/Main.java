/*
  This file is part of JOP, the Java Optimized Processor
    see <http://www.jopdesign.com/>

  Copyright (C) 2001-2008, Martin Schoeberl (martin@jopdesign.com)

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/*
	Author: T�rur Biskopst� Str�m (torur.strom@gmail.com)
*/
package org.reprap;

import javax.realtime.PriorityParameters;
import javax.safetycritical.Mission;
import javax.safetycritical.MissionSequencer;
import javax.safetycritical.PeriodicEventHandler;
import javax.safetycritical.Safelet;
import javax.safetycritical.StorageParameters;
import javax.safetycritical.JopSystem;

public class Main implements Safelet
{

	private MissionSequencer seq = null;
	
	public long immortalMemorySize(){return 0;}
	
	
	public static void main(String[] args) {
		JopSystem.startMission(new Main());
	}
	
	@Override
	public MissionSequencer getSequencer()
	{
		if(seq == null)
		{
			seq = new RepRapMissionSequencer();
		}
		return seq;
	}
	
	public class RepRapMissionSequencer extends MissionSequencer
	{
		private Mission mission = null;
		
		RepRapMissionSequencer()
		{
			super(new PriorityParameters(0),new StorageParameters(1000, null, 0,0));
		}
				
		@Override
		protected Mission getNextMission()
		{
			if(mission == null)
			{
				mission = new RepRapMission();
			}
			return mission;
		}
		
		public class RepRapMission extends Mission
		{
			PeriodicEventHandler peh1 = null;
			PeriodicEventHandler peh2 = null;
			PeriodicEventHandler peh3 = null;
			PeriodicEventHandler peh4 = null;
			
			@Override
			public long missionMemorySize()
			{
				return 50;
			}
			
			@Override
			protected void initialize()
			{
				if(peh1 == null)
				{
					peh1 = RepRapController.getInstance();
				}
				if(peh2 == null)
				{
					//peh2 = SerialController.getInstance();
					//peh2 = new IICController();
				}
				if(peh3 == null)
				{
					peh3 = CommandController.getInstance();
				}
				if(peh4 == null)
				{
					peh4 = Command.getInstance();
				}
			}
		}
	}
}
			
			
			
			