# Printed after apply. Use public IPs for Remote Desktop, private IPs inside the appliances.
output "source_public_ip" { value = aws_instance.source.public_ip }
output "source_private_ip" { value = aws_instance.source.private_ip } # discovery source (Step 6)
output "discovery_public_ip" { value = aws_instance.discovery.public_ip }
output "replication_public_ip" { value = aws_instance.replication.public_ip }
output "replication_private_ip" { value = aws_instance.replication.private_ip }
