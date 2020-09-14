const fs = require('fs');
const parser = require('xml2json');
const path = require('path');
const AdmZip = require('adm-zip');
const rimraf = require("rimraf");

let project;

function updateProject() {
    const processesPath = path.join(getExtractedProjectPath(), 'processes');
    const processes = fs.readdirSync(processesPath);

    processes.forEach(process => {
        if (process && path.extname(process) === '.xml') {
            const processFileName = process;
            const extensionsFileName = process.replace('.bpmn20.xml',
                '-extensions.json');
            updateVariableMappingRepresentation(processFileName,
                extensionsFileName);
        }
    });
}

function retrieveMappableEntitiesIds(xmlParsedFile, xmlNameSpace) {
    xmlProcessElements = xmlParsedFile[`${xmlNameSpace}definitions`][`${xmlNameSpace}process`];
    const mappableEntityTypes = ['userTask', 'serviceTask', 'callActivity'];
    const entityIds = [];

    for (let [key] of Object.entries(xmlProcessElements)) {

        var entity = `${key}`.replace(xmlNameSpace, '');

        if (mappableEntityTypes.includes(entity)) {
            //entities of the same kind get parsed together as an array
            if (Array.isArray(xmlProcessElements[key])) {
                xmlProcessElements[key].forEach((item) => {
                    entityIds.push(item.id);
                });
            } else {
                entityIds.push(xmlProcessElements[key].id);
            }
        }
    }
    return entityIds;
}

function updateVariableMappingRepresentation(processName, extensionsFileName) {
    try {
        const processContent = fs.readFileSync(
            path.join(getExtractedProjectPath(), 'processes', processName));
        const xmlParsedFile = JSON.parse(
            parser.toJson(processContent, {reversible: true}));
        const xmlNameSpace = extractNameSpace(xmlParsedFile);
        const processId = xmlParsedFile[`${xmlNameSpace}definitions`][`${xmlNameSpace}process`].id;
        const entityIds = retrieveMappableEntitiesIds(xmlParsedFile,
            xmlNameSpace);

        updateProcessExtensions(extensionsFileName, processId, entityIds);

    } catch (error) {
        console.log(error);
    }
}

function extractNameSpace(xmlParsedFile) {
    let xmlNameSpaceArray = Object.keys(xmlParsedFile)[0].split(':');
    let xmlNameSpace;
    if (xmlNameSpaceArray.length == 2) {
        xmlNameSpace = xmlNameSpaceArray[0] + ':';
    } else {
        xmlNameSpace = '';
    }
    return xmlNameSpace;
}

function updateProcessExtensions(processExtensionsName, processId, entityIds) {
    try {

        const fileContent = fs.readFileSync(getExtractedProjectPath() + '/processes/' + processExtensionsName);
        const processExtensions = JSON.parse(fileContent);

        console.log('\n\t* Update of file ' + "'" + processExtensionsName + "'" + ' started');
        
        console.log('\n\t\t- Current variable mapping representation: ', processExtensions.extensions[processId].mappings);

        //make the 'Send all variables' cases explicit
        entityIds.forEach((entityId) => {
            if (processExtensions.extensions[processId].mappings.hasOwnProperty(
                entityId) === false) {
                processExtensions.extensions[processId].mappings[entityId] = {
                    "mappingType": "MAP_ALL"
                };
            }
        });

        //make the 'Don't send variables' use case implicit
        const mappingToDelete = {
            "inputs": {},
            "outputs": {}
        };
        allMappings = processExtensions.extensions[processId].mappings;

        for (let [key] of Object.entries(allMappings)) {
            if (JSON.stringify(allMappings[key]) === JSON.stringify(mappingToDelete)) {
                delete allMappings[key];
            }
        }

        console.log('\n\t\t- Updated variable mapping representation: ', allMappings);

        const updatedProcessExtensions = JSON.stringify(processExtensions);

        try {
            fs.writeFileSync(path.join(getExtractedProjectPath(), 'processes', processExtensionsName), updatedProcessExtensions);
            console.log('\n\t* Update of file ' + "'" + processExtensionsName + "'" + ' successfully completed');
        } catch (error) {
            console.log('\n\t* Failed to update file: ' + processExtensionsName);
            console.log(error);
        }

    } catch (e) {
        console.log(e);
    }
}

function extractProject() {
    if (path.extname(project) === '.zip') {
        const zip = new AdmZip(project);
        try {
            zip.extractAllTo(getExtractedProjectPath(), true);
        } catch (error) {
            console.log(error);
        }
    }
}

function compressNewProject() {
    const zip = new AdmZip();
    try {
        zip.addLocalFolder(getExtractedProjectPath());
    } catch (error) {
        console.log(error);
    }
    const updatedProjectName = getProjectName() + '_updated.zip';
    try {
        zip.writeZip(path.join(getProjectDirectoryPath(), updatedProjectName));
    } catch (error) {
        console.log(error);
    }
}

function removeProjectFolder() {
    rimraf.sync(getExtractedProjectPath());
}

function getProjectName() {
    return path.basename(project).replace('.zip', '');
}

function getProjectDirectoryPath() {
    return project.substring(0, project.lastIndexOf('/'));
}

function getExtractedProjectPath() {
    return project.replace('.zip', '');
}

function initScript() {
    project = process.argv[2];
    console.log(`\n1. Extracting folder: ${project}`);
    extractProject();
    console.log(`\n2. Updating ${getProjectName()} project`);
    updateProject();
    console.log(`\n3. Compressing folder`);
    compressNewProject();
    console.log(`\n4. Cleaning up`);
    removeProjectFolder();
    console.log(`\nProject updated successfully!`);
}

initScript();
