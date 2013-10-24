package com.appdynamics.connectors.vsphere;


import java.net.URL;
import com.singularity.ee.connectors.api.IControllerServices;
import com.singularity.ee.connectors.api.InvalidObjectException;
import com.singularity.ee.connectors.entity.api.IComputeCenter;
import com.singularity.ee.connectors.entity.api.IImage;
import com.singularity.ee.connectors.entity.api.IImageStore;
import com.singularity.ee.connectors.entity.api.IMachine;
import com.singularity.ee.connectors.entity.api.IProperty;
import com.vmware.vim25.mo.Datacenter;
import com.vmware.vim25.mo.ServiceInstance;


class DatacenterLocator
{
	private static final DatacenterLocator INSTANCE = new DatacenterLocator();
	private final Object connectorLock = new Object();

	
	/**
	 * Private constructor on singleton.
	 */
	private DatacenterLocator() {}
	
	/**
	 * Function to get ConnectorLocator instance.
	 * @return
	 */
	public static DatacenterLocator getInstance()
	{
		return INSTANCE;
	}
	
	/**
	 * Function to get ServiceInstance from target ip, username and password.
	 * @param ipAddress				Target ipaddress.
	 * @param username				Target username.
	 * @param password				Target password.
	 * @param controllerServices	controllerServices object.
	 * @return VMware connection object, ServiceInstance.
	 */
	private ServiceInstance getServiceInstance(String ipAddress, String username, String password)
	{
		synchronized (connectorLock)
		{
			
			try
			{
				String urlStr = "https://" + ipAddress + "/sdk";
				ServiceInstance vmware = new ServiceInstance(new URL(urlStr), username, password, true);
				
				return vmware;
			}
			catch (Exception e) 
			{
				return null;
			}
		}
	}
	
	/**
	 * Returns a newly created VMwareDatacenter object from given credentials
	 * @param controllerServices	controllerServices object
	 * @param ipAddress				Ip address of target vCenter Server
	 * @param username				Username for vCenter Server
	 * @param password				Password for vCenter Server
	 * @param dcPath				Path to target datacenter on vCenter Server
	 * @return VMwareDatacenter object, not to be confused with the VI SDK's own Datacenter object
	 * @throws InvalidObjectException
	 */
	private VMwareDatacenter getDatacenter(IControllerServices controllerServices, String ipAddress, String username, String password, String dcPath) throws InvalidObjectException
	{

		
		ServiceInstance si = getServiceInstance(ipAddress, username, password);
		if(si == null)
		{
			throw new InvalidObjectException("Could not authenticate vCenter Server.");
		}
		Datacenter dc = (Datacenter) Utils.getChildEntityByDir(si.getRootFolder(), dcPath);
		if(dc == null)
		{
			throw new InvalidObjectException("Datacenter not found.");
		}
		
		return new VMwareDatacenter(controllerServices, dc);
		
		
	}
	
	private VMwareDatacenter getDatacenter(IProperty[] properties, IControllerServices controllerServices) throws InvalidObjectException
	{
		String ipAddress = controllerServices.getStringPropertyValueByName(properties, Utils.VSPHERE_IP_ADDRESS);
		String username = controllerServices.getStringPropertyValueByName(properties, Utils.VSPHERE_USERNAME);
		String password = controllerServices.getStringPropertyValueByName(properties, Utils.VSPHERE_PASSWORD);
		String dcPath = controllerServices.getStringPropertyValueByName(properties, Utils.DATACENTER_PATH);
		
		return getDatacenter(controllerServices, ipAddress, username, password, dcPath);
	}

	public VMwareDatacenter getDatacenter(IComputeCenter computeCenter, IControllerServices controllerServices) throws InvalidObjectException
	{
		return getDatacenter(computeCenter.getProperties(), controllerServices);
	}
	
	public VMwareDatacenter getDatacenter(IImageStore imageStore, IControllerServices controllerServices) throws InvalidObjectException
	{
		return getDatacenter(imageStore.getProperties(), controllerServices);
	}
	
	public VMwareDatacenter getDatacenter(IImage image, IControllerServices controllerServices) throws InvalidObjectException
	{
		
		return getDatacenter(image.getImageStore().getProperties(), controllerServices);
	}

	
	public VMwareDatacenter getDatacenter(IMachine machine, IControllerServices controllerServices) throws InvalidObjectException
	{
		
		return getDatacenter(machine.getImage().getImageStore().getProperties(), controllerServices);
	}
	
	
}
