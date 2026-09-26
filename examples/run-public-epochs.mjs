import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {readFile} from '../tools/edf.mjs';
import {report} from '../_build/js/release/build/cmd/bridge/bridge.js';

// This is a specific public-data workflow, not an interpretation of arbitrary T1 labels.
const [input,output,...extra]=process.argv.slice(2);
if(!input||!output||extra.length)throw Error('Usage: node examples/run-public-epochs.mjs S001R03.edf NEW_OUTPUT_DIRECTORY');
const data=readFile(input),sha=createHash('sha256').update(data).digest('hex');
if(sha!=='3427c8d01bff1380bc9ab9f27a35ece2af5dfadf3e291bbc05eb66e4dadbfe2e')throw Error('Expected the pinned PhysioNet S001R03.edf; use tools/fetch-public-eeg.py');
const annotations=JSON.parse(report(data,JSON.stringify({command:'annotations'}))),epochs=[];
for(let annotation=0;annotation<annotations.length;annotation++){
 if(annotations[annotation].text!=='T1')continue;
 const options={command:'epoch',annotation,signals:[0,8,32],before:.25,after:.25,max_samples:10000};
 const result=JSON.parse(report(data,JSON.stringify(options)));
 if(!result.complete)throw Error('Unexpected incomplete event window');
 epochs.push({options,result});
}
if(!epochs.length)throw Error('No selected events');
fs.mkdirSync(output); // Existing directories are deliberately refused.
const quote=value=>`"${String(value).replaceAll('"','""')}"`,files=[];
for(const {options,result} of epochs){
 const lines=['annotation,event,signal,label,record,sample,time_seconds,event_relative_seconds,digital,physical,unit'];
 for(const channel of result.channels)for(const sample of channel.samples)lines.push([
  options.annotation,quote(result.annotation.text),channel.signal,quote(channel.label),sample.record,sample.sample,
  sample.time,sample.time-result.annotation.onset,sample.digital,sample.physical,quote(channel.unit)
 ].join(','));
 const name=`epoch-${options.annotation}.csv`,csv=lines.join('\n')+'\n';
 fs.writeFileSync(path.join(output,name),csv,{flag:'wx'});
 files.push({file:name,sha256:createHash('sha256').update(csv).digest('hex'),options,annotation:result.annotation,start:result.start,end:result.end,samples:result.samples,complete:result.complete});
}
const manifest={source:'https://physionet.org/content/eegmmidb/1.0.0/',doi:'10.13026/C28G6P',license:'ODC-By-1.0',attribution:'EEG Motor Movement/Imagery Dataset, Gerwin Schalk and colleagues, PhysioNet',inputSha256:sha,files,
 scope:'T1 annotations in S001R03 only; no clinical interpretation, resampling, filtering or inference of labels for other runs'};
fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({output:path.resolve(output),epochs:files.length,samples:files.reduce((n,f)=>n+f.samples,0),inputSha256:sha}));
