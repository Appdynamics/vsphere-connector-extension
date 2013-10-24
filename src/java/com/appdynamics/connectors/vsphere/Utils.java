package com.appdynamics.connectors.vsphere;

import java.util.Date;
import com.vmware.vim25.mo.Datacenter;
import com.vmware.vim25.mo.Folder;
import com.vmware.vim25.mo.ManagedEntity;
import com.vmware.vim25.mo.VirtualMachine;

public class Utils {

	
	// Compute center constants
	public static final String VSPHERE_USERNAME = "Username";
	public static final String VSPHERE_PASSWORD = "Password";
	public static final String VSPHERE_IP_ADDRESS = "IP Address";
	public static final String DATACENTER_PATH = "Datacenter Path";
	
	// Image properties related constants
	public static final String IMAGE_PATH = "Image Path";
	
	// IMachineDescriptor related constants
	public static final String CLONE_TYPE = "Clone Type";
		public static final String FULL_CLONE_TYPE = "Full";
		public static final String LINKED_CLONE_TYPE = "Linked";
	//public static final String CLONE_DESTINATION_TYPE = "Clone Destination";
		//public static final String SAME_CLONE_DESTINATION = "Same";
		//public static final String SPECIFY_CLONE_DESTINATION = "Specify";
	public static final String CLONE_DESTINATION_FOLDER = "Clone Destination Folder";
	public static final String HOST_IP = "Host IP";
	public static final String DEST_DATASTORE_NAME = "Host Datastore Name";
	//public static final String KEEP_VM_ON_TERMINATE = "Keep VM On Terminate";
	
	//Other
	public static final String CLONE_APPEND_SUFFIX = "_AD_";
	public static final String FULL_CLONE_APPEND_SUFFIX = "_FullClone_";
	public static final String LINKED_CLONE_APPEND_SUFFIX = "_LinkedClone_";
	public static final int MAX_CLONE_COUNT = 99;
	
	public static String getVmNameFromPath(String path)
	{
		int index = path.lastIndexOf('/');
		return path.substring(index+1);
	}
	
	

	public static String getFolderNameFromPath(String path) 
	{
		int index = path.lastIndexOf('/');
		if(index==-1)return "";
		return path.substring(0, index);
	}
	
	public static boolean isVmPoweredOff(VirtualMachine vm)
	{
		return (vm.getRuntime().getPowerState().toString().compareTo("poweredOff") == 0);
	}
	
	public static boolean isVmPoweredOn(VirtualMachine vm)
	{
		return (vm.getRuntime().getPowerState().toString().compareTo("poweredOn") == 0);
	}
	
	//Used for generating a unique arbitrary string
	public static String getUniqueName()
	{
		Date date = new Date();
		return date.toString().replaceAll("\\s", "");
	}
	
	public static ManagedEntity getChildEntity (ManagedEntity parent, String targetName)
	{
		
		if(targetName.compareTo("") == 0) return parent;
		
		String parentType = parent.getMOR().type;
		Folder haystack;
		
		try
		{
			
			if (parentType.compareTo("Datacenter")==0)  //Searches the VMFolder of a Datacenter object
			{
				Datacenter temp_dc = (Datacenter) parent;
				haystack = temp_dc.getVmFolder();		
			}
			else if(parentType.compareTo("Folder")==0)	
			{
				haystack = (Folder) parent;
			}else 
			{
				return null;
			}
			

			ManagedEntity[] children = haystack.getChildEntity();
			for(ManagedEntity child : children)
			{
				if (child.getName().compareTo(targetName) == 0)	
				{
					return child;
				}
			}
		}
		catch (Exception e){
			return null;
		}
			
		return null;
	}
	
	//Returns null if not found
	public static ManagedEntity getChildEntityByDir(ManagedEntity parent, String dir)
	{
		if(parent==null)return null;
		
		if (dir.indexOf('/')==-1)
		{
			return getChildEntity(parent, dir);
		}
		
		String head = dir.substring(0, dir.indexOf('/'));
		String tail = dir.substring(head.length()+1, dir.length());
		
		return getChildEntityByDir(getChildEntity(parent, head), tail);
	}

}
