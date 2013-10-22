#!/bin/bash
# Author: william2003[at]gmail[dot]com
#	  duonglt[at]engr[dot]ucsb[dot]edu
# Date: 09/30/2008
#
# Custom Shell script to clone Virtual Machines for Labs at UCSB ResNet for ESXi, script will take number of agruments based on a golden image along with
# designated virtual machine lab name and a range of VMs to be created.
#######################################################################################################################################################

ESXI_VMWARE_VIM_CMD=/bin/vim-cmd

validateUserInput() {
	#sanity check to make sure you're executing on an ESX 3.x host
	if [ ! -f ${ESXI_VMWARE_VIM_CMD} ]; then
       		echo "This script is meant to be executed on VMware ESXi" 1>&2
        	exit 1
	fi
	if ! echo ${GOLDEN_VM} | egrep -i '[0-9A-Za-z]+.vmx$' > /dev/null && [[ ! -f "${GOLDEN_VM}"  ]]; then
                echo "Error: Golden VM Input is not valid" 1>&2
                exit 1
        fi
	#sanity check to verify Golden VM is offline before duplicating
	${ESXI_VMWARE_VIM_CMD} vmsvc/get.runtime ${GOLDEN_VM_VMID} | grep "powerState" | grep "poweredOff" > /dev/null 2>&1
	if [ ! $? -eq 0 ]; then
        	echo "Master VM status is currently online, not registered or does not exist." 1>&2
        	exit 1
	fi
        if [ "${DEVEL_MODE}" -eq 1 ]; then echo "Golden VM is offline"; fi

        local mastervm_dir=$(dirname "${GOLDEN_VM}")
        if ls "${mastervm_dir}" | grep -E '(delta|-rdm.vmdk|-rdmp.vmdk)' > /dev/null 2>&1; then
                echo "Master VM contains either a Snapshot or Raw Device Mapping. " 1>&2
                exit 1
        fi
        if [ "${DEVEL_MODE}" -eq 1 ]; then echo "Snapshots and RDMs were not found"; fi

        if ! grep "ethernet0.present = \"true\"" "${GOLDEN_VM}" > /dev/null 2>&1; then
                echo "Master VM does not contain valid eth0 vnic, script requires eth0 to be present and valid." 1>&2
                exit 1
        fi
	vmdks_count=`grep scsi "${GOLDEN_VM}" | grep fileName | awk -F "\"" '{print $2}' | wc -l`
        vmdks=`grep scsi "${GOLDEN_VM}" | grep fileName | awk -F "\"" '{print $2}'`
        if [ "${vmdks_count}" -gt 1 ]; then echo "Found more than 1 VMDK associated with the Master VM, script only supports a single VMDK" 1>&2 ; 
		exit 1; fi
        if ! echo ${START_COUNT} | egrep '^[0-9]+$' > /dev/null; then
                echo "Error: START value is not valid" 1>&2
                exit 1
        fi
        if ! echo ${END_COUNT} | egrep '^[0-9]+$' > /dev/null; then
                echo "Error: END value is not valid" 1>&2
                exit 1
        fi
        #sanity check to verify your range is positive
        if [ "${START_COUNT}" -gt "${END_COUNT}" ]; then
                echo "Your Start Count can not be greater or equal to your End Count." 1>&2
                exit 1
        fi
        #end of sanity check
}

#sanity check on the # of args
if [ $# != 4 ]; then
echo "Invalid parameters for the script." 1>&2
        exit 1
fi

#DO NOT TOUCH INTERNAL VARIABLES
#set variables
GOLDEN_VM=$1
VM_NAMING_CONVENTION=$2
START_COUNT=$3
END_COUNT=$4

GOLDEN_VM_PATH=`echo ${GOLDEN_VM%%.vmx*}`
GOLDEN_VM_NAME=`grep "displayName" ${GOLDEN_VM} | awk '{print $3}' | sed 's/"//g'`
GOLDEN_VM_VMID=`${ESXI_VMWARE_VIM_CMD} vmsvc/getallvms | grep ${GOLDEN_VM_NAME} | awk '{print $1}'`
STORAGE_PATH=`echo ${GOLDEN_VM%/*/*}`

validateUserInput


#start duplication
COUNT=$START_COUNT
MAX=$END_COUNT
START_TIME=`date`
S_TIME=`date +%s`
TOTAL_VM_CREATE=$(( ${END_COUNT} - ${START_COUNT} + 1 ))

LC_EXECUTION_DIR=/tmp/esxi_linked_clones_run.$$
mkdir -p ${LC_EXECUTION_DIR}
LC_CREATED_VMS=${LC_EXECUTION_DIR}/newly_created_vms.$$
touch ${LC_CREATED_VMS}

WATCH_FILE=${LC_CREATED_VMS}
EXPECTED_LINES=${TOTAL_VM_CREATE}

while sleep 5;
do
	REAL_LINES=$(wc -l < "${WATCH_FILE}")
	REAL_LINES=`echo ${REAL_LINES} | sed 's/^[ \t]*//;s/[ \t]*$//'`
	P_RATIO=$(( (${REAL_LINES} * 100 ) / ${EXPECTED_LINES} ))
	P_RATIO=${P_RATIO%%.*}
	clear
	if [ ${REAL_LINES} -ge ${EXPECTED_LINES} ]; then
		break
	fi
done &

while [ "$COUNT" -le "$MAX" ];
do
		FINAL_VM_NAME="${VM_NAMING_CONVENTION}"
        mkdir -p ${STORAGE_PATH}/$FINAL_VM_NAME

        cp ${GOLDEN_VM_PATH}.vmx ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx

	VMDK_PATH=`grep scsi0:0.fileName ${GOLDEN_VM_PATH}.vmx | awk '{print $3}' | sed 's/"//g'`
	sed -i 's/displayName = "'${GOLDEN_VM_NAME}'"/displayName = "'${FINAL_VM_NAME}'"/' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx
        sed -i '/scsi0:0.fileName/d' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx
        echo "scsi0:0.fileName = \"${STORAGE_PATH}/${GOLDEN_VM_NAME}/${VMDK_PATH}\"" >> ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx
	sed -i 's/nvram = "'${GOLDEN_VM_NAME}.nvram'"/nvram = "'${FINAL_VM_NAME}.nvram'"/' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx
	sed -i 's/extendedConfigFile = "'${GOLDEN_VM_NAME}.vmxf'"/extendedConfigFile = "'${FINAL_VM_NAME}.vmxf'"/' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx
        sed -i '/ethernet0.generatedAddress/d' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx > /dev/null 2>&1
	sed -i '/ethernet0.addressType/d' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx > /dev/null 2>&1
        sed -i '/uuid.location/d' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx > /dev/null 2>&1
        sed -i '/uuid.bios/d' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx > /dev/null 2>&1
	sed -i '/sched.swap.derivedName/d' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx > /dev/null 2>&1

        ${ESXI_VMWARE_VIM_CMD} solo/registervm ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx > /dev/null 2>&1

	FINAL_VM_VMID=`${ESXI_VMWARE_VIM_CMD} vmsvc/getallvms | grep ${FINAL_VM_NAME} | awk '{print $1}'`

        ${ESXI_VMWARE_VIM_CMD} vmsvc/snapshot.create ${FINAL_VM_VMID} Cloned ${FINAL_VM_NAME}_Cloned_from_${GOLDEN_VM_NAME} > /dev/null 2>&1

        #output to file to later use
        echo "${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx" >> "${LC_CREATED_VMS}"

        COUNT=$(( $COUNT + 1 ))
done

sleep 10

END_TIME=`date`
E_TIME=`date +%s`

#grab mac addresses of newly created VMs (file to populate dhcp static config)
if [ -f ${LC_CREATED_VMS} ]; then
        for i in `cat ${LC_CREATED_VMS}`;
        do
		TMP_LIST=${LC_EXECUTION_DIR}/vm_list.$$
                VM_P=`echo ${i##*/}`
                VM_NAME=`echo ${VM_P%.vmx*}`
                VM_MAC=`grep ethernet0.generatedAddress "${i}" | awk '{print $3}' | sed 's/\"//g' | head -1 | sed 's/://g'`
		while [ "${VM_MAC}" == "" ]
		do
			sleep 1
			VM_MAC=`grep ethernet0.generatedAddress "${i}" | awk '{print $3}' | sed 's/\"//g' | head -1 | sed 's/://g'`
		done
                echo "${VM_NAME}  ${VM_MAC}" >> ${TMP_LIST}
        done
        LCS_OUTPUT="lcs_created_on-`date +%F-%H%M%S`"
        cat ${TMP_LIST} | sed 's/[[:digit:]]/ &/1' | sort -k2n | sed 's/ //1' > "${LCS_OUTPUT}"
fi

rm -rf ${LC_EXECUTION_DIR}
echo "Successfully created Linked clone"