#!/usr/bin/env python3
"""
Deploy to all Container App instances.

This script runs after azd deploys to the first instance and updates
the additional Container App instances with the new image.
"""
import os
import sys
import subprocess

def main():
    resource_group = os.getenv("AZURE_RESOURCE_GROUP")
    container_app_name = os.getenv("AZURE_CONTAINER_APP_NAME")
    image_name = os.getenv("SERVICE_API_IMAGE_NAME")

    print("\033[36mDeploying to all Container App instances...\033[0m")
    print(f"\033[90mResource Group: {resource_group}\033[0m")
    print(f"\033[90mContainer App Base Name: {container_app_name}\033[0m")
    print(f"\033[90mImage: {image_name}\033[0m")

    # Update primary instance (already deployed by azd)
    print()
    print(f"\033[32mPrimary instance {container_app_name} already updated by azd\033[0m")

    # Update additional instances (1 and 2)
    for i in range(1, 3):
        instance_name = f"{container_app_name}-{i}"
        print()
        print(f"\033[33mUpdating instance: {instance_name}\033[0m")
        
        try:
            subprocess.run(
                ["az", "containerapp", "update", 
                 "--name", instance_name, 
                 "--resource-group", resource_group, 
                 "--image", image_name, 
                 "--output", "none"],
                check=True,
                shell=True
            )
            print(f"\033[32mSuccessfully updated {instance_name}\033[0m")
        except subprocess.CalledProcessError:
            print(f"\033[31mFailed to update {instance_name}\033[0m")

    print()
    print("\033[32mAll Container App instances have been updated!\033[0m")

if __name__ == "__main__":
    main()
