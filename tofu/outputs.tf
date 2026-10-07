output "instances" {
  value = {
    for name, inst in incus_instance.vm :
    name => {
      running = inst.running
    }
  }
}