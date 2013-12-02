# Logs message local to this VM
LOG()
{
    msg=$1;
    echo `date` "$msg" >> "$LOG_FILE"
}
 
# Function to  install Hadoop
install_hadoop()
{
    # Install the JDK
    LOG "Installing JDK from $DOWNLOAD_DIR"
    cd $DOWNLOAD_DIR
    chmod +x $DOWNLOAD_DIR/$JDK_PKG_NAME
    yes |  $DOWNLOAD_DIR/$JDK_PKG_NAME
    if [ "$?" != "0" ] ; then
        LOG "Error installing JDK "
        exit 1
    fi
    
    JDK_version=`ls /usr/java/ | grep jdk`
    echo "export JAVA_HOME=/usr/java/$JDK_version" >> /etc/profile
    echo "export JRE_HOME=/usr/java/$JDK_version/jre" >> /etc/profile
    echo "export CLASSPATH=.:\$JAVA_HOME/lib:\$JRE_HOME/lib:\$CLASSPATH" >> /etc/profile
    echo "export PATH=\$JAVA_HOME/bin:\$JRE_HOME/bin:\$PATH" >> /etc/profile
    
    source /etc/profile 
    if [ "$?" != "0" ] ; then
        LOG "Fail to config /etc/profile to add java environment variables.You can config it manually."
    fi
 
    LOG "Installing  Hadoop 1.2.1"
    tar xvfz $DOWNLOAD_DIR/hadoop-1.2.1-bin.tar.gz  -C /opt
    if [ "$?" != "0" ] ; then
        LOG "Error installing Cloudera Hadoop"
        exit 1
    fi
    return 0
}
 
# Function to start up hadoop
config_hadoop()
{
    local HADOOP_CONF=/opt/hadoop-1.2.1/
    # Some how alternatives not setting correctly
    #cp -r $HADOOP_CONF/conf.pseudo $HADOOP_CONF/conf.my_cluster
    #alternatives --install $HADOOP_CONF/conf hadoop-0.20-conf $HADOOP_CONF/conf.my_cluster 50
    
    LOG "Configuring Cloudera Hadoop"
    HADOOP_MASTER=$1
 
    # Put master name into the config files
    sed  s/localhost/$HADOOP_MASTER/ < $HADOOP_CONF/core-site.xml > $HADOOP_CONF/core-site.new.xml
 
    sed s/localhost/$HADOOP_MASTER/ < $HADOOP_CONF/mapred-site.xml > $HADOOP_CONF/mapred-site.new.xml
 
    sed s/localhost/$HADOOP_MASTER/ < $HADOOP_CONF/masters > $HADOOP_CONF/masters.new
 
    add_slave_hostname slaves
    if [ "$?" != "0" ] ; then
        LOG "Failed to config slave for hadoop."
        return 1
    fi
 
    mv -f $HADOOP_CONF/core-site.new.xml $HADOOP_CONF/core-site.xml
    mv -f $HADOOP_CONF/mapred-site.new.xml $HADOOP_CONF/mapred-site.xml
    mv -f $HADOOP_CONF/masters.new $HADOOP_CONF/masters
 
    # config hadoop for dynamic refresh cluster info.
    touch -f /opt/hadoop-1.2.1/datanode_allowlist
    touch -f /opt/hadoop-1.2.1/tasktracker_allowlist
    sed -i '/<\/configuration>/d' /opt/hadoop-1.2.1/hdfs-site.xml
    cat <<AAA >> /opt/hadoop-1.2.1/hdfs-site.xml
  <property>
    <name>dfs.hosts</name>
    <value>/opt/hadoop-1.2.1/datanode_allowlist</value>
  </property>
  <property>
    <name>mapred.hosts</name>
    <value>/opt/hadoop-1.2.1/tasktracker_allowlist</value>
  </property>
AAA
    echo "</configuration>" >> /opt/hadoop-1.2.1/hdfs-site.xml
 
    JDK_version=`ls /usr/java | grep jdk`
    command="s#JAVA_HOME=.*\$#JAVA_HOME=/usr/java/$JDK_version#"
    sed -i $command $HADOOP_CONF/hadoop-env.sh
    sed -i "s/^#.*JAVA_HOME=/  export JAVA_HOME=/" $HADOOP_CONF/hadoop-env.sh
 
    LOG "Finish config Cloudera Hadoop"
 
    #    chkconfig hadoop-0.20-namenode --add
    #    chkconfig hadoop-0.20-namenode on
    #    chkconfig hadoop-0.20-jobtracker --add
    #    chkconfig hadoop-0.20-jobtracker on
    #    chkconfig hadoop-0.20-secondarynamenode --add
    #    chkconfig hadoop-0.20-secondarynamenode on
    #    chkconfig hadoop-0.20-tasktracker --add
    #    chkconfig hadoop-0.20-tasktracker on
    #    chkconfig hadoop-0.20-datanode --add
    #    chkconfig hadoop-0.20-datanode on
    config_ssh
 
    # change sudoers file to use "sudo" command in script.
    #sed -i 's/Defaults.*requiretty/#Defaults    requiretty/' /etc/sudoers
    #if [ "$?" != "0" ] ; then
    #    LOG "Failed to change /etc/sudoers file."
    #    return 1
    #fi
 
    LOG "Start Hadoop cluster..."
    echo "Y" | /opt/hadoop-1.2.1/bin/hadoop namenode -format    
    #sudo -u hadoop /usr/lib/hadoop-0.20/bin/start-all.sh
    #if [ "$?" != "0" ] ; then
    #    LOG "Failed to start Hadoop cluster, you can run /usr/lib/hadoop-0.20/bin/start-all.sh manually."
    #fi 
    LOG "Format namenode successfully."
 
    return 0
}
 
config_ssh()
{
    return 0
}
 
add_slave_hostname()
{
    local HADOOP_CONF=/opt/hadoop-1.2.1/ 
    local file=$1
    if [ -f $HADOOP_CONF/${file}.temp ];then
        rm -f $HADOOP_CONF/${file}.temp
    fi 
    mv $HADOOP_CONF/${file} $HADOOP_CONF/${file}.temp
    
    # config input file to add hostnames of all slaves.
    config_file="$HADOOP_CONF/${file}"
    slave_hostname=`echo $HadoopSlaveTier_HOSTNAMES | sed "s/;/ /g"`
    array_hostname=($slave_hostname)
    
    len=${#array_hostname[@]}
    index=0
    while [ $index -lt $len ];do
        echo "${array_hostname[$index]}" >> $config_file
        let ++index
    done
 
    if [ "$?" != "0" ] ; then
        LOG "Failed to config file $config_file."
        return 1
    fi
 
    return 0 
}
 
add_to_hosts()
{
    ip_address="$1"
    host_name="$2"
    LOG "ip address $ip_address host_name $host_name" 
    file1="/etc/hosts";
 
    cp -f $file1 ${file1}.bak
    sed -i '/127.0.0.1/d' $file1
 
    tmp_ip_address=`echo $ip_address | sed "s/;/ /g"`
    tmp_host_name=`echo $host_name | sed "s/;/ /g"`
    array_ip_address=($tmp_ip_address)
    array_host_name=($tmp_host_name)
    len=${#array_ip_address[@]}
    index=0
    sed -i -e /^$/d $file1
    while [ $index -lt $len ];do
        sed -i -e /${array_ip_address[$index]}/d $file1
        echo "${array_ip_address[$index]}   ${array_host_name[$index]}" >> $file1
        let ++index
    done
 
    if [ "$?" != "0" ] ; then
        LOG "Failed to add < $ip_address   $host_name > into $file1"
        return 1
    fi
 
    return 0
}
 
#================= Main Entry =======================================
 
# Where to output log file
LOG_FILE=/tmp/hadoopMaster.log
 
# Where to download files
DOWNLOAD_DIR="/hadoop_package"
JDK_PKG_NAME="jdk-6u30-linux-x64-rpm.bin" 
# OK.  Do the work.
 
HadoopMasterTier_IP_ADDRS=`ifconfig  eth0 | grep "inet addr" | awk '{print $2}'| awk -F ":" '{print $2}'`
HadoopMasterTier_HOSTNAMES=`hostname`
 
 
HadoopSlaveTier_IP_ADDRS=$1
HadoopSlaveTier_HOSTNAMES=$2
 
LOG "PATH $PATH"
PATH=$PATH:/usr/sbin
PATH=$PATH:/sbin
LOG "PATH $PATH"
 
LOG "Starting........."
 
#LOG_EVENT "Post-provisioning script started" 
 
LOG "Current Action is CREATE"
 
#add_to_hosts "$HadoopSlaveTier_IP_ADDRS" "$HadoopSlaveTier_HOSTNAMES"
install_hadoop
if [ "$?" != "0" ] ; then
    exit 99
fi
 
config_hadoop
if [ "$?" != "0" ] ; then
    exit 99
fi
 
JobTraker=`echo "$HadoopMasterTier_HOSTNAMES:50030"`
HDFS=`echo "$HadoopMasterTier_HOSTNAMES:50070"`
LOG "JobTracker_url=$JobTraker"
LOG "HDFS_url=$HDFS"
 
LOG "End....."
 
exit 0
