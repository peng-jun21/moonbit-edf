#!/usr/bin/env node
// The host owns file paths and process IO; binary and signal work is MoonBit.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { report, transform } from '../_build/js/release/build/cmd/bridge/bridge.js';

function readBounded(filename,limit) {
  const fd=fs.openSync(filename,'r');
  try {
    const stat=fs.fstatSync(fd);
    if (!stat.isFile() || !Number.isSafeInteger(stat.size) || stat.size<0 || stat.size>limit)
      throw new Error(`input must be a regular file <= ${limit} bytes`);
    // Read from the checked descriptor, bounded by the observed size plus one
    // sentinel byte. A separate path stat cannot cap readFileSync allocation.
    const buffer=Buffer.alloc(stat.size+1);
    let length=0;
    while (length<buffer.length) {
      const count=fs.readSync(fd,buffer,length,buffer.length-length,null);
      if (count===0) break;
      length+=count;
    }
    if (length!==stat.size) throw new Error('input changed size during read; retry a stable file');
    return buffer.subarray(0,length);
  } finally {fs.closeSync(fd);}
}

export function readFile(filename) {
  return readBounded(filename,268435456);
}

export function writeTransform(input,output,options) {
  if (fs.existsSync(output)) throw new Error('output exists; choose a new path');
  const data=options.command==='create' ? new Uint8Array() : readFile(input);
  const result=transform(data,JSON.stringify(options));
  fs.writeFileSync(output,result,{flag:'wx'});
  return {output,bytes:result.length};
}

const writes=new Set(['copy','select','crop','plus','create']);
const reads=new Set(['inspect','validate','stats','annotations','gaps','flat','csv','channel','window','window-csv']);
function main(args) {
  if (!args.length || args[0]==='--help') {
    console.log('MoonEDF\n  inspect|validate|stats|annotations|gaps|flat|csv|channel|window|window-csv INPUT [OPTIONS.json]\n  copy|select|crop|plus INPUT OUTPUT [OPTIONS.json]\n  create OUTPUT OPTIONS.json\nUse JSON options from README. Existing files are never overwritten.'); return;
  }
  const [command,...rest]=args;
  if (!writes.has(command) && !reads.has(command)) throw new Error('unknown command; use --help');
  const create=command==='create', write=writes.has(command);
  if (rest.length<(write?2:1) || rest.length>(create?2:write?3:2)) throw new Error('wrong argument count; use --help');
  const optionsPath=create?rest[1]:rest[write?2:1];
  const options=optionsPath?JSON.parse(readBounded(optionsPath,1000000).toString('utf8')):{};
  if (!options || Array.isArray(options) || typeof options!=='object') throw new Error('options must be an object');
  options.command=command;
  if (write) console.log(JSON.stringify(writeTransform(create?null:rest[0],create?rest[0]:rest[1],options)));
  else {
    const result=report(readFile(rest[0]),JSON.stringify(options));
    const value=JSON.parse(result);
    process.stdout.write(typeof value?.text==='string'?value.text:result+'\n');
  }
}
if (process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {main(process.argv.slice(2));} catch(e) {console.error(`MoonEDF: ${e.message??e}`);process.exitCode=2;}
}
