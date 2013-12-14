/**
 * Copyright 2013 AppDynamics, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.appdynamics.connectors.vsphere;

import static com.singularity.ee.controller.KAppServerConstants.CONTROLLER_SERVICES_HOST_NAME_PROPERTY_KEY;
import static com.singularity.ee.controller.KAppServerConstants.CONTROLLER_SERVICES_PORT_PROPERTY_KEY;
import static com.singularity.ee.controller.KAppServerConstants.DEFAULT_CONTROLLER_PORT_VALUE;

import java.net.InetAddress;
import java.net.UnknownHostException;
import com.singularity.ee.agent.resolver.AgentResolutionEncoder;
import com.singularity.ee.connectors.api.IControllerServices;
import com.singularity.ee.connectors.api.InvalidObjectException;
import com.singularity.ee.connectors.entity.api.IAccount;
import com.singularity.ee.connectors.entity.api.IComputeCenter;
import com.singularity.ee.connectors.entity.api.IImage;
import com.singularity.ee.connectors.entity.api.IMachine;
import com.singularity.ee.connectors.entity.api.IMachineDescriptor;
import com.singularity.ee.connectors.entity.api.MachineState;
import com.vmware.vim25.ManagedObjectReference;
import com.vmware.vim25.OptionValue;
import com.vmware.vim25.TaskInfoState;
import com.vmware.vim25.VirtualMachineCloneSpec;
import com.vmware.vim25.VirtualMachineConfigSpec;
import com.vmware.vim25.VirtualMachineRelocateDiskMoveOptions;
import com.vmware.vim25.VirtualMachineRelocateSpec;
import com.vmware.vim25.mo.ComputeResource;
import com.vmware.vim25.mo.Datacenter;
import com.vmware.vim25.mo.Datastore;
import com.vmware.vim25.mo.Folder;
import com.vmware.vim25.mo.HostSystem;
import com.vmware.vim25.mo.InventoryNavigator;
import com.vmware.vim25.mo.ManagedEntity;
import com.vmware.vim25.mo.Task;
import com.vmware.vim25.mo.VirtualMachine;

public class VMwareDatacenter 
{
	private IControllerServices controllerServices;

	private Datacenter dc;
	
	private static final Object counterLock = new Object();
	private static volatile long counter;

	public VMwareDatacenter(IControllerServices controllerServices, Datacenter dc)
	{
		this.controllerServices = controllerServices;
		this.dc = dc;
	}
	

	private void powerUpClone(VirtualMachine clone) throws Exception
	{
		if(Utils.isVmPoweredOff(clone))
		{
			clone.powerOnVM_Task(null);
		}
	}


	private void powerDownClone(VirtualMachine clone) throws Exception
	{
		if(Utils.isVmPoweredOn(clone))
		{
			Task powerOffTask = clone.powerOffVM_Task();
			while(powerOffTask.getTaskInfo().getState() != TaskInfoState.success)
			{
				if(powerOffTask.getTaskInfo().getState() == TaskInfoState.error)
				{
					throw new Exception("Power off failure.");
				}
			}
		}
	}


	/**
	 * Returns the datastore object that the cloned VM will be place in
	 * @param image
	 * @param machineDescriptor
	 * @return null if not found
	 * @throws InvalidObjectException
	 */
	private Datastore getCloneDatastore(IImage image, IMachineDescriptor machineDescriptor) throws InvalidObjectException
	{
		String datastoreName = controllerServices.getStringPropertyValueByName(machineDescriptor.getProperties(), Utils.DEST_DATASTORE_NAME);
		
		//If destination datastore is left blank, use same datastore as image
		if (datastoreName.isEmpty())
		{
			VirtualMachine imageVM = getImageVM(image);
			try 
			{
				return imageVM.getDatastores()[0]; //Assumes 1 datastore associated with VM
			} catch (Exception e) 
			{
				return null;
			}
		}
		
		//Gets datastore specified by machineDescriptor
		try {
			for (Datastore ds : dc.getDatastores() )
			{
				if (datastoreName.compareTo(ds.getName())==0)
				{
					return ds;
				}	
			}
		} catch (Exception e) 
		{
			return null;
		} 
		return null;
		

	}
	

	private HostSystem getHostSystemByIp(String hostIp)
	{	
		try 
		{
			Folder computeResources = dc.getHostFolder();
			return (HostSystem) new InventoryNavigator(computeResources).searchManagedEntity("HostSystem", hostIp);
		} catch (Exception e) 
		{
			return null;
		}
	}


	private ManagedObjectReference getCloneResourcePoolMOR(IImage image, IMachineDescriptor machineDescriptor) throws InvalidObjectException
	{
		String hostIP = controllerServices.getStringPropertyValueByName(machineDescriptor.getProperties(), Utils.HOST_IP);
		if(hostIP.isEmpty())
		{
			VirtualMachine imageVM = getImageVM(image);
			
			if (imageVM.getConfig().template)
			{
				throw new InvalidObjectException("Must specify host for template image.");
			}
			
			try 
			{
				return imageVM.getResourcePool().getMOR();
			} catch (Exception e) 
			{
				return null;
			}
		}
		return ((ComputeResource)getHostSystemByIp(hostIP).getParent()).getResourcePool().getMOR();
	}
	

	private VirtualMachineRelocateSpec setRelocateSpec(IImage image, IMachineDescriptor machineDescriptor) throws InvalidObjectException 
	{	
		VirtualMachineRelocateSpec relocateSpec = new VirtualMachineRelocateSpec();
		
		relocateSpec.pool = getCloneResourcePoolMOR(image, machineDescriptor);
		relocateSpec.datastore = getCloneDatastore(image, machineDescriptor).getMOR();
		
		//Linked or Full Clone
		String cloneType = controllerServices.getStringPropertyValueByName(machineDescriptor.getProperties(), Utils.CLONE_TYPE);
		if(cloneType.compareTo(Utils.LINKED_CLONE_TYPE) == 0)
		{
			relocateSpec.diskMoveType = VirtualMachineRelocateDiskMoveOptions.moveChildMostDiskBacking.toString();
		}
		
		return relocateSpec;
	}

	private VirtualMachineConfigSpec setConfigSpec(IComputeCenter computeCenter) throws UnknownHostException 
	{
		String controllerHost =  System.getProperty(CONTROLLER_SERVICES_HOST_NAME_PROPERTY_KEY, InetAddress.getLocalHost().getHostAddress());
	
		int controllerPort = Integer.getInteger(CONTROLLER_SERVICES_PORT_PROPERTY_KEY, DEFAULT_CONTROLLER_PORT_VALUE);
		
		IAccount account = computeCenter.getAccount();
		String accountName = account.getName();
		String accessKey = account.getAccessKey();
		
		AgentResolutionEncoder agentResolutionEncoder = new AgentResolutionEncoder(controllerHost, controllerPort, accountName, accessKey);
		OptionValue optVal = new OptionValue();
		optVal.setKey("guestinfo.appdynamics.userdata");
		optVal.setValue(agentResolutionEncoder.encodeAgentResolutionInfo());
		
		
		
		
		OptionValue optVal2 = new OptionValue();
		optVal2.setKey("guestinfo.herp");
		optVal2.setValue("derp");
		
		
		
		
		
		OptionValue[] optVals = {optVal, optVal2};
		
		VirtualMachineConfigSpec configSpec = new VirtualMachineConfigSpec();
		configSpec.setExtraConfig(optVals);
		
		
		return configSpec;
	}


	private Folder getCloneFolder(IImage image, IMachineDescriptor machineDescriptor) throws InvalidObjectException
	{
		String destFolderPath = controllerServices.getStringPropertyValueByName(machineDescriptor.getProperties(), Utils.CLONE_DESTINATION_FOLDER); 

		if(destFolderPath.isEmpty()) //Gets parent folder of imageVM
		{
			VirtualMachine imageVM = getImageVM(image);
			return (Folder) imageVM.getParent();
		}
	
		ManagedEntity result = Utils.getChildEntityByDir(dc, destFolderPath);
		if (result == null)
		{
			throw new InvalidObjectException("Invalid destination.");
		}
		if(result.getMOR().type.compareTo("Datacenter") == 0)
		{
			try 
			{
				return ((Datacenter) result).getVmFolder();
			} catch (Exception e) 
			{
				return null;
			} 
		}
		return (Folder) Utils.getChildEntityByDir(dc, destFolderPath);
	
	}


	/**
	 * Returns the associated VirtualMachine object of the image
	 * @param image
	 * @return 
	 * @throws InvalidObjectException when the vm is not found
	 */
	public VirtualMachine getImageVM(IImage image) throws InvalidObjectException
	{
		String VMPath = controllerServices.getStringPropertyValueByName(image.getProperties(), Utils.IMAGE_PATH);
		
		VirtualMachine vm = null;
		try 
		{
			vm = (VirtualMachine) Utils.getChildEntityByDir(dc, VMPath);
		} catch (Exception e) 
		{
			throw new InvalidObjectException("Image not found on compute center.");
		}
		
		if( vm==null)
		{
			throw new InvalidObjectException("Image not found on compute center.");
		}
		return vm;
	}

	/**
	 * Returns the associated VirtualMachine object of the clone
	 * @param machine
	 * @return 
	 * @throws InvalidObjectException when the vm is not found
	 */
	public VirtualMachine getCloneVM(IMachine machine) throws InvalidObjectException
	{
		Folder cloneDestinationFolder = getCloneFolder(machine.getImage(), machine.getMachineDescriptor());
		return (VirtualMachine) Utils.getChildEntity(cloneDestinationFolder, machine.getName());
	}
	
	/**
	 * Searches for unpowered clones of the image and powers up one if found. Creates a new clone if none are found.
	 * @param image
	 * @param machineDescriptor
	 * @param computeCenter
	 * @return
	 * @throws Exception
	 */
	public IMachine createClone(IImage image, IMachineDescriptor machineDescriptor, IComputeCenter computeCenter) throws Exception
	{
	
		VirtualMachine	imageVM = getImageVM(image);
		Folder cloneDestFolder = getCloneFolder(image, machineDescriptor);
		
		long count;

		synchronized (counterLock)
		{
			count = counter++;
		}
		
		
		String cloneName = "AD_" + System.currentTimeMillis() + count;
		String internalName = cloneName;
		
		VirtualMachineCloneSpec cloneSpec = new VirtualMachineCloneSpec();
		cloneSpec.setLocation(setRelocateSpec(image, machineDescriptor));
		cloneSpec.setPowerOn(true);
		cloneSpec.setTemplate(false);		
		
		try {
			imageVM.cloneVM_Task(cloneDestFolder, cloneName, cloneSpec);
		} catch (Exception e) 
		{
			throw e;
		} 


		return controllerServices.createMachineInstance(cloneName, internalName, computeCenter, machineDescriptor, image, controllerServices.getDefaultAgentPort());

	}


	
	/**
	 * Restarts the guest OS of the clone. Does a hard reboot if there is no guest OS or VMware Tools is not installed on the guest OS.
	 * @param machine
	 * @throws Exception
	 */
	public void rebootClone(IMachine machine) throws Exception 
	{
		VirtualMachine clone = getCloneVM(machine);
		try 
		{
			clone.rebootGuest();
		} catch (Exception e)
		{
			try 
			{
				powerDownClone(clone);
				powerUpClone(clone);
			} catch (Exception e1)
			{
				throw new Exception("Restart machine failed");
			}
		}
	}

	/**
	 * Powers down guest OS and deletes the VM if the "Destroy on Terminate" machineDescriptor property is true.
	 * @param machine
	 * @throws Exception
	 */
	public void deleteClone(IMachine machine) throws Exception
	{
		VirtualMachine clone = getCloneVM(machine);
		powerDownClone(clone);
		
		clone.destroy_Task();

	}

	
	
	/**
	 * Refreshes the machine status as well as IP address.
	 * @param machine
	 * @throws Exception
	 */
	public void updateCloneStatus(IMachine machine) throws Exception
	{
		VirtualMachine clone = getCloneVM(machine);

		if(clone == null)
		{
			if(machine.getState()==MachineState.STARTING)
			{
				return;
			}
			
			machine.setState(MachineState.STOPPED);
			return;
		}
		

		String state = clone.getRuntime().powerState.toString();

		if(machine.getState()==MachineState.STARTING)
		{
			if (state.compareTo("poweredOn")==0)
			{
				clone.reconfigVM_Task(setConfigSpec(machine.getComputeCenter()));
				machine.setState(MachineState.STARTED);
				
			}
		}
		
		
		if(machine.getState()==MachineState.STARTED)
		{
			machine.setIpAddress(clone.getGuest().ipAddress);
		}
	}

}
