# Alfresco Modeling Project Updater

## Introduction

This script will update your projects to make sure they are valid between versions M5 and M6 of Activiti Enterprise. It will update your processes to ensure that existing projects work with the latest version of the Alfresco Modeling Application. 

## Prerequisites

### Node.js

[Node.js](https://nodejs.org) is a JavaScript runtime built using an event-driven, non-blocking I/O model that makes it lightweight and efficient. `Node.js`  uses [npm](https://www.npmjs.com/) as a public registry and package system.

Confirm that you're running the latest version of `node.js`.
To check the version, run the following command in a terminal.

    node -v

## Before you start

### Backup your projects

Make sure you have a backup of your current projects should something fail during the update process. You should expect nothing to go wrong but it's better to play safe.

### Installing dependencies

Run the following command to download the packages needed for this script and its dependencies.

    npm install

## How to use

Once you've completed the previous steps you'll be able to use Alfresco's Project Updater.

This script takes the name of the project as the only parameter. Notice that it's expecting the zip file, not the extracted folder.

It you have cloned this repo into the same directory where you have your projects you just need to specify the project you want to update.

    node alfresco-project-updater-M9-M10 yourProject.zip

If the projects are in a different directory you need to pass the relative path to your project and the script will do the rest.

    node alfresco-project-updater-M9-M10 ../FOLDER/SUBFOLDER/yourProject.zip

After the script has finished, you will get a new compressed project compatible with the latest version. 

Finally, upload the new project zip files into the Alfresco Modeler App and deploy the application.

## Notes

This script will name the newly created project after the original project name and the `_updated` suffix. This is done to avoid overwriting the original project content.

It is advisable not to run the script more than once per project as it could result in some metadata corruption.
