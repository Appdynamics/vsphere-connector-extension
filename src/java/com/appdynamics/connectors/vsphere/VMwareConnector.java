/*
 *   Copyright 2018. AppDynamics LLC and its affiliates.
 *   All Rights Reserved.
 *   This is unpublished proprietary source code of AppDynamics LLC and its affiliates.
 *   The copyright notice above does not evidence any actual or intended publication of such source code.
 *
 */
package com.appdynamics.connectors.vsphere;

import java.util.logging.Logger;

import com.singularity.ee.connectors.api.ConnectorException;
import com.singularity.ee.connectors.api.IConnector;
import com.singularity.ee.connectors.api.IControllerServices;
import com.singularity.ee.connectors.api.InvalidObjectException;
import com.singularity.ee.connectors.entity.api.IComputeCenter;
import com.singularity.ee.connectors.entity.api.IImage;
import com.singularity.ee.connectors.entity.api.IImageStore;
import com.singularity.ee.connectors.entity.api.IMachine;
import com.singularity.ee.connectors.entity.api.IMachineDescriptor;
import com.vmware.vim25.mo.VirtualMachine;


public class VMwareConnector implements IConnector
{
	private static Logger logger = Logger.getLogger(VMwareConnector.class.getName());

	private IControllerServices controllerServices;

	/**
	 * Public no-arg constructor is required by the connector framework.
	 */
	public VMwareConnector() {}



	public void setControllerServices(IControllerServices controllerServices)
	{
		this.controllerServices = controllerServices;
	}

	public int getAgentPort()
	{
		return controllerServices.getDefaultAgentPort();
	}


	@Override
	public void validate(IComputeCenter computeCenter) throws InvalidObjectException, ConnectorException 
	{
		logger.info("Validating ComputeCloud: " + computeCenter.getName());
	
		try	{
			@SuppressWarnings("unused")
			VMwareDatacenter dc = DatacenterLocator.getInstance().getDatacenter(computeCenter, controllerServices);
		} 
		catch (InvalidObjectException e) 
		{
			throw e;
		} 
		catch(Exception e)	
		{
			throw new ConnectorException(e.getMessage());
		}
	}



	@Override
	public void validate(IImageStore imageStore) throws InvalidObjectException,	ConnectorException 
	{
		logger.info("Validating ImageStore: " + imageStore.getName());
	
		try	
		{
			@SuppressWarnings("unused")
			VMwareDatacenter dc = DatacenterLocator.getInstance().getDatacenter(imageStore, controllerServices);
		} 
		catch (InvalidObjectException e) 
		{
			throw e;
		} 
		catch(Exception e)	
		{
			throw new ConnectorException(e.getMessage());
		}
	}



	@Override
	public void validate(IImage image) throws InvalidObjectException, ConnectorException 
	{
		logger.info("Validating Image: " + image.getName());
	
		try	
		{
			VMwareDatacenter dc = DatacenterLocator.getInstance().getDatacenter(image, controllerServices);
			
			@SuppressWarnings("unused")
			VirtualMachine vm = dc.getImageVM(image);
	
		} 
		catch (InvalidObjectException e) 
		{
			throw e;
		} 
		catch(Exception e)	
		{
			throw new ConnectorException(e.getMessage());
		}
	}



	@Override
	public IMachine createMachine(IComputeCenter computeCenter, IImage image, IMachineDescriptor machineDescriptor)	throws InvalidObjectException, ConnectorException 
	{
		logger.info("Spinning up clone: " + image.getName());
		try
		{
			VMwareDatacenter dc = DatacenterLocator.getInstance().getDatacenter(image, controllerServices);
			IMachine machine = dc.createClone(image, machineDescriptor, computeCenter);
			return machine;
		}
		catch (InvalidObjectException e) 
		{
			throw e;
		}
		catch (Exception e)	
		{
			throw new ConnectorException(e.getMessage(), e);
		}


	}


	@Override
	public void refreshMachineState(IMachine machine) throws InvalidObjectException, ConnectorException 
	{
		try
		{
			VMwareDatacenter dc = DatacenterLocator.getInstance().getDatacenter(machine, controllerServices);
			dc.updateCloneStatus(machine);
		}
		catch(Exception e)
		{
			throw new ConnectorException("Failed to refresh machine state: ", e);
		}
	}

	@Override
	public void terminateMachine(IMachine machine)throws InvalidObjectException, ConnectorException 
	{
		logger.info("Powering off machine: " + machine.getName());
		
		try
		{
			VMwareDatacenter dc = DatacenterLocator.getInstance().getDatacenter(machine, controllerServices);
			dc.deleteClone(machine);
		}
		catch (InvalidObjectException e) 
		{
			throw e;
		} 
		catch(Exception e)	
		{
			throw new ConnectorException(e.getMessage());
		}
	}

	@Override
	public void restartMachine(IMachine machine) throws InvalidObjectException,	ConnectorException 
	{
		logger.info("Restarting machine: " + machine.getName());
		
		try
		{
			VMwareDatacenter dc = DatacenterLocator.getInstance().getDatacenter(machine, controllerServices);
			dc.rebootClone(machine);
		}
		catch (InvalidObjectException e) 
		{
			throw e;
		} 
		catch(Exception e)	
		{
			throw new ConnectorException(e.getMessage());
		}
	}






	@Override
	public void deleteImage(IImage image) throws InvalidObjectException, ConnectorException
	{
		// [CORE-1948] This is not strictly needed for the VMWare connector implementation...

	}		

	@Override
	public void refreshImageState(IImage image) throws InvalidObjectException, ConnectorException 
	{

	}
	

	@Override
	public void configure(IComputeCenter computeCenter)
			throws InvalidObjectException, ConnectorException {
		// TODO Auto-generated method stub

	}

	@Override
	public void configure(IImageStore imageStore)
			throws InvalidObjectException, ConnectorException {
		// TODO Auto-generated method stub

	}

	@Override
	public void configure(IImage image) throws InvalidObjectException,
	ConnectorException {
		// TODO Auto-generated method stub

	}

	@Override
	public void unconfigure(IComputeCenter computeCenter)
			throws InvalidObjectException, ConnectorException {
		// TODO Auto-generated method stub

	}

	@Override
	public void unconfigure(IImageStore imageStore)
			throws InvalidObjectException, ConnectorException {
		// TODO Auto-generated method stub

	}

	@Override
	public void unconfigure(IImage image) throws InvalidObjectException,
	ConnectorException {
		// TODO Auto-generated method stub

	}


}



