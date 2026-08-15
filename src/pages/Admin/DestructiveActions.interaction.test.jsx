import assert from 'node:assert/strict';
import test from 'node:test';
import React from 'react';
import {act,create} from 'react-test-renderer';
import {AccountModal} from './UserManagement.jsx';
import {FormatClinicDangerZone} from '../Settings.jsx';

globalThis.IS_REACT_ACT_ENVIRONMENT=true;

const textOf=node=>node.children.map(child=>typeof child==='string'?child:textOf(child)).join('');
const buttonNamed=(root,name)=>root.findAllByType('button').find(button=>textOf(button).trim()===name);
const deferred=()=>{let resolve;const promise=new Promise(done=>{resolve=done;});return{promise,resolve};};

const activeUser={
  id:'11111111-1111-4111-8111-111111111111',fullName:'Target Doctor',clinicEmail:'doctor@clinic.test',
  role:'doctor',specialization:'Dentistry',phone:'',isActive:true,isLinked:true,deletionStatus:'active',approvedAt:'2026-01-01',
};

async function renderAccount(overrides={}){
  let renderer;
  await act(async()=>{
    renderer=create(<AccountModal user={activeUser} currentUserId="22222222-2222-4222-8222-222222222222"
      loadUser={async()=>activeUser} deleteUser={async()=>({success:true})}
      onClose={()=>{}} onSaved={async()=>{}} onDeleted={async()=>{}} {...overrides}/>);
    await Promise.resolve();await Promise.resolve();
  });
  return renderer;
}

test('Delete Account click opens visible confirmation and exact phrase gates one request',async()=>{
  const request=deferred();let calls=0;let target;
  const renderer=await renderAccount({deleteUser:async userId=>{calls+=1;target=userId;return request.promise;}});
  const open=buttonNamed(renderer.root,'Delete Account');
  assert.equal(open.props.type,'button');assert.equal(open.props.disabled,false);
  await act(async()=>{open.props.onClick();});
  const dialogs=renderer.root.findAll(node=>node.props.role==='dialog');
  const confirmation=dialogs.find(dialog=>dialog.props['aria-labelledby']==='delete-account-title');
  assert.ok(confirmation);assert.match(textOf(confirmation),/DELETE doctor@clinic\.test/);
  const input=confirmation.findByProps({autoComplete:'off'});
  let finalButton=buttonNamed(confirmation,'Delete Account');
  assert.equal(finalButton.props.type,'button');assert.equal(finalButton.props.disabled,true);
  await act(async()=>{input.props.onChange({target:{value:'DELETE wrong@clinic.test'}});});
  finalButton=buttonNamed(confirmation,'Delete Account');assert.equal(finalButton.props.disabled,true);
  await act(async()=>{input.props.onChange({target:{value:'DELETE doctor@clinic.test'}});});
  finalButton=buttonNamed(confirmation,'Delete Account');assert.equal(finalButton.props.disabled,false);
  await act(async()=>{finalButton.props.onClick();finalButton.props.onClick();await Promise.resolve();});
  assert.equal(calls,1);assert.equal(target,activeUser.id);
  await act(async()=>{request.resolve({success:true});await request.promise;});
});

test('self-delete stays disabled before confirmation can open',async()=>{
  const renderer=await renderAccount({currentUserId:activeUser.id});
  const open=buttonNamed(renderer.root,'Delete Account');
  assert.equal(open.props.disabled,true);
  assert.match(textOf(renderer.root),/You cannot delete your own account/);
});

test('Format click opens visible confirmation and exact phrase gates one parameterless action',async()=>{
  const request=deferred();let calls=0;let reloads=0;let renderer;
  await act(async()=>{renderer=create(<FormatClinicDangerZone userRole="admin"
    formatAction={async()=>{calls+=1;return request.promise;}} reload={()=>{reloads+=1;}} schedule={callback=>callback()}/>);});
  const open=buttonNamed(renderer.root,'Format Clinic Data');
  assert.equal(open.props.type,'button');
  await act(async()=>{open.props.onClick();});
  const confirmation=renderer.root.findByProps({'aria-labelledby':'format-clinic-title'});
  assert.equal(confirmation.props.role,'dialog');assert.match(textOf(confirmation),/FORMAT CLINIC/);
  const input=confirmation.findByProps({autoComplete:'off'});
  let finalButton=buttonNamed(confirmation,'Format Clinic Data');assert.equal(finalButton.props.disabled,true);
  await act(async()=>{input.props.onChange({target:{value:'format clinic'}});});
  finalButton=buttonNamed(confirmation,'Format Clinic Data');assert.equal(finalButton.props.disabled,true);
  await act(async()=>{input.props.onChange({target:{value:'FORMAT CLINIC'}});});
  finalButton=buttonNamed(confirmation,'Format Clinic Data');assert.equal(finalButton.props.disabled,false);
  await act(async()=>{finalButton.props.onClick();finalButton.props.onClick();await Promise.resolve();});
  assert.equal(calls,1);assert.equal(reloads,0);
  await act(async()=>{request.resolve({formatted:true});await request.promise;});
  assert.equal(reloads,1);
});

test('Format action is not rendered for Doctor or Receptionist',async()=>{
  for(const role of ['doctor','receptionist']){
    let renderer;await act(async()=>{renderer=create(<FormatClinicDangerZone userRole={role}/>);});
    assert.equal(renderer.toJSON(),null);
  }
});
