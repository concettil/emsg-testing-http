const fs = require('fs');          // Modulo per la gestione del file system
const http = require('http');      // Modulo per effettuare richieste HTTP
const https = require('https');    // Modulo per effettuare richieste HTTPS
const ISOBoxer = require('codem-isoboxer');  // Libreria per analizzare i box ISO BMFF (come MP4)
const argv = require('minimist')(process.argv.slice(2));  // Modulo per analizzare gli argomenti della riga di comando
const xml2js = require('xml2js');  // Modulo per il parsing dell'XML

const help = argv.help;
if (help) {
    const helpMessage = `
    Simple command line tool for reading emsg boxes in MP4.

    Available commands:
      --help                  Show this help description.

      --manifest <url>        Specify the URL for the DASH manifest (MPD).
    `;
    console.log(helpMessage);
    return;
}

const manifestUrl = argv.manifest;

if (!manifestUrl) {
    throw Error('No argument provided for manifest URL');
}

function getSegment(url) {
    const protocol = url.startsWith('https') ? https : http;
    return new Promise((resolve, reject) => {
        protocol.get(url, { encoding: null }, (response) => {
            if (response.statusCode >= 300) {
                reject(Error(`Invalid status code: ${response.statusCode} - ${response.statusMessage}`));
                response.resume();
                return;
            }
            let data = [];
            let connectionError;
            response.on('data', (chunk) => {
                data.push(chunk);
            });
            response.on('error', (error) => {
                connectionError = error;
            });
            response.on('close', () => {
                if (connectionError) {
                    reject(connectionError);
                } else {
                    resolve(Buffer.concat(data));
                }
            });
        });
    });
}

function logBoxesFromArrayBuffer(buffer) {
    const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
    const parsedFile  = ISOBoxer.parseBuffer(arrayBuffer);
    const emsgBoxes = parsedFile.boxes.filter((box) => box.type == 'emsg');

    if (emsgBoxes.length == 0) {
        console.warn('No emsg box present in segment.');
    } else {
        emsgBoxes.forEach((emsgBox) => {
            const unwrap = ({
                                size,
                                type,
                                version,
                                flags,
                                scheme_id_uri,
                                value,
                                timescale,
                                presentation_time,
                                presentation_time_delta,
                                event_duration,
                                id,
                                message_data
                            }) => ({
                size,
                type,
                version,
                flags,
                scheme_id_uri,
                value,
                timescale,
                presentation_time,
                presentation_time_delta,
                event_duration,
                id,
                message_data: (new TextDecoder()).decode(message_data)
            });
            console.log(unwrap(emsgBox));
        });
    }
}

async function processManifest(url) {
    const manifestData = await getSegment(url);
    const manifestXml = manifestData.toString();
    const parser = new xml2js.Parser();
    const manifest = await parser.parseStringPromise(manifestXml);

    const adaptationSets = manifest.MPD.Period[0].AdaptationSet;
    const videoRepresentations = adaptationSets
        .filter(set => set.$.mimeType === 'video/mp4')
        .flatMap(set => set.Representation);

    if (videoRepresentations.length === 0) {
        throw new Error('No video representations found in the manifest.');
    }

    videoRepresentations.sort((a, b) => parseInt(a.$.width, 10) - parseInt(b.$.width, 10));
    const lowestResolutionRepresentation = videoRepresentations[0];
    const representationId = lowestResolutionRepresentation.$.id;
    const segmentTemplate = adaptationSets.find(set => set.$.mimeType === 'video/mp4').SegmentTemplate[0];

    const mediaUrl = segmentTemplate.$.media.replace('$RepresentationID$', representationId).replace('$Time$', segmentTemplate.SegmentTimeline[0].S[0].$.t);

    const baseUrl = url.substring(0, url.lastIndexOf('/'));
    const chunkUrl = `${baseUrl}/${mediaUrl}`;

    console.log(`Fetching segment from URL: ${chunkUrl}`);

    const segmentBuffer = await getSegment(chunkUrl);
    logBoxesFromArrayBuffer(segmentBuffer);
}

processManifest(manifestUrl).catch(error => {
    console.error('Error processing manifest:', error);
});
