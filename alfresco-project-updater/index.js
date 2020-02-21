const fs = require('fs');
const shortid = require('shortid');
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
            const processId = 'Process_' + shortid();
            const processFileName = process;
            const extensionsFileName = process.replace('.bpmn20.xml', '-extensions.json');
            updateProcessXML(processFileName, processId);
            updateProcessExtensionsJSON(extensionsFileName, processId);
        }
    });
}

function updateProcessXML(processName, processId) {
    try {
        const processContent = fs.readFileSync(path.join(getExtractedProjectPath(), 'processes', processName));
        const xmlParsedFile = JSON.parse(parser.toJson(processContent, { reversible: true }));
        let xmlNameSpace = Object.keys(xmlParsedFile)[0].split(':')[0];
        xmlNameSpace = xmlNameSpace ? xmlNameSpace + ':' : '';
        xmlParsedFile[`${xmlNameSpace}definitions`].id = xmlParsedFile[`${xmlNameSpace}definitions`][`${xmlNameSpace}process`].id.replace('process', 'model');
        xmlParsedFile[`${xmlNameSpace}definitions`][`${xmlNameSpace}process`].id = processId;
        xmlParsedFile[`${xmlNameSpace}definitions`]['bpmndi:BPMNDiagram']['bpmndi:BPMNPlane'].bpmnElement = processId;

        const updatedXML = parser.toXml(JSON.stringify(xmlParsedFile));
        try {
            fs.writeFileSync(path.join(getExtractedProjectPath(), 'processes', processName), updatedXML);
            console.log('\t-> Process file: ' + processName + ' successfully updated');
        } catch (error) {
            console.log(error);
        }
    } catch (error) {
        console.log(error);
    }
}

function updateProcessExtensionsJSON(processExtensionsName, processId) {
    try {
        const processContent = fs.readFileSync(getExtractedProjectPath() + '/processes/' + processExtensionsName);
        const processExtensions = JSON.parse(processContent);
        const oldProcessExtensions = processExtensions.extensions;
        processExtensions.extensions = {
            [processId]: oldProcessExtensions
        }

        const updatedProcessExtensions = JSON.stringify(processExtensions);
        try {
            fs.writeFileSync(path.join(getExtractedProjectPath(), 'processes', processExtensionsName), updatedProcessExtensions);
            console.log('\t-> Extensions file: ' + processExtensionsName + ' successfully updated');
        } catch (error) {
            console.log(error);
        }
    } catch (error) {
        console.log(error);
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
    console.log(`\n2. Updating ${getProjectName()}`);
    updateProject();
    console.log(`\n3. Compressing folder`);
    compressNewProject();
    console.log(`\n4. Cleaning up`);
    removeProjectFolder();
    console.log(`\nProject updated successfully!`);
}

initScript();
