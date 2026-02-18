for vm in $(virsh list --name --state-running); do
    echo -n "$vm: ";
    virsh dommemstat $vm | grep rss | awk '{print $2/1024 " MB"}';
done

