import React, { useState, useMemo } from 'react';
import { Canvas } from '@react-three/fiber';
import { OrbitControls, Environment, ContactShadows, RoundedBox, Center, Text } from '@react-three/drei';
import * as THREE from 'three';
import { FDI_TOOTH_MAP, TOOTH_TYPES, TOOTH_STATUS } from '../data/toothData';

// Medical Theme Colors (Light Mode)
const STATUS_COLORS = {
  [TOOTH_STATUS.HEALTHY]: '#FFFFFF',
  [TOOTH_STATUS.PROBLEM]: '#EF4444', 
  [TOOTH_STATUS.TREATED]: '#3B82F6',
  [TOOTH_STATUS.MISSING]: '#64748B',
  SELECTED: '#FACC15', // Yellow for selection
};

const getToothPosition = (id) => {
  const tooth = FDI_TOOTH_MAP[id];
  const isUpper = tooth.arch === 'upper';
  const quadrant = tooth.quadrant;
  const positionInQuadrant = parseInt(id.toString()[1]);

  let archIndex;
  if (quadrant === 1 || quadrant === 4) {
    archIndex = - (positionInQuadrant - 0.5);
  } else {
    archIndex = (positionInQuadrant - 0.5);
  }

  const a = 0.22; 
  const x = archIndex * 0.52; 
  const z = a * x * x; 
  const y = isUpper ? 0.9 : -0.9;
  
  const tangent = 2 * a * x;
  const angle = Math.atan(tangent);
  
  return { pos: [x, y, z], rot: [isUpper ? Math.PI : 0, -angle, 0] };
};

const Tooth = ({ id, status, isSelected, onClick, showNumbers }) => {
  const [hovered, setHovered] = useState(false);
  const toothInfo = FDI_TOOTH_MAP[id];
  const { pos, rot } = useMemo(() => getToothPosition(id), [id]);
  const isMissing = status === TOOTH_STATUS.MISSING;

  const getColor = () => {
    if (isSelected) return STATUS_COLORS.SELECTED;
    return STATUS_COLORS[status] || STATUS_COLORS[TOOTH_STATUS.HEALTHY];
  };

  const type = toothInfo.type;
  let crownArgs = [0.4, 0.6, 0.3]; 
  if (type === TOOTH_TYPES.MOLAR) crownArgs = [0.7, 0.6, 0.65];
  if (type === TOOTH_TYPES.PREMOLAR) crownArgs = [0.55, 0.6, 0.45];
  if (type === TOOTH_TYPES.CANINE) crownArgs = [0.45, 0.7, 0.4];

  const scale = isSelected ? 1.15 : 1;

  return (
    <group position={pos} rotation={rot} scale={[scale, scale, scale]}>
      {showNumbers && (parseInt(id.toString()[1]) % 2 === 1 || isSelected) && (
        <Text
          position={[0, toothInfo.arch === 'upper' ? 0.8 : -0.8, 0.4]}
          fontSize={0.12}
          color="#6B7280"
          anchorX="center"
          anchorY="middle"
          rotation={toothInfo.arch === 'upper' ? [Math.PI, 0, 0] : [0, 0, 0]}
        >
          {id}
        </Text>
      )}

      <RoundedBox 
        args={crownArgs} 
        radius={0.1} 
        smoothness={4}
        castShadow
        onClick={(e) => { e.stopPropagation(); onClick(id); }}
        onPointerOver={(e) => { e.stopPropagation(); setHovered(true); document.body.style.cursor = 'pointer'; }}
        onPointerOut={() => { setHovered(false); document.body.style.cursor = 'auto'; }}
      >
        <meshPhysicalMaterial 
          color={getColor()} 
          roughness={isMissing ? 0.8 : 0.2} 
          metalness={0.1} 
          clearcoat={isMissing ? 0 : 0.8}
          opacity={isMissing ? 0.35 : 1}
          transparent={isMissing}
          emissive={hovered && !isSelected ? '#10B981' : '#000000'}
          emissiveIntensity={hovered ? 0.3 : 0}
        />
      </RoundedBox>

      {/* Root/Gums base */}
      {!isMissing && (
        <mesh position={[0, toothInfo.arch === 'upper' ? -0.4 : -0.4, 0]}>
          <capsuleGeometry args={[0.15, 0.3, 4, 8]} />
          <meshStandardMaterial color={isSelected ? '#FACC15' : '#E5E7EB'} />
        </mesh>
      )}
    </group>
  );
};

export default function Dental3DModel({ toothData, selectedToothId, onToothSelect, viewMode, showNumbers }) {
  const upperTeeth = [...Array(8)].flatMap((_, i) => [`1${8-i}`, `2${i+1}`]);
  const lowerTeeth = [...Array(8)].flatMap((_, i) => [`4${8-i}`, `3${i+1}`]);

  return (
    <div style={{ width: '100%', height: '100%', position: 'relative' }}>
      <Canvas shadows camera={{ position: [0, 0, 7.5], fov: 32 }}>
        <ambientLight intensity={0.6} />
        <directionalLight position={[10, 10, 10]} intensity={1} castShadow />
        <pointLight position={[-10, -10, -10]} intensity={0.5} />
        
        <Center>
          <group rotation={[0.1, 0, 0]}>
            {/* Gums Visualization */}
            <mesh rotation={[Math.PI/2, 0, 0]} position={[0, 0.9, -0.2]}>
                <torusGeometry args={[1.8, 0.1, 12, 24, Math.PI]} />
                <meshStandardMaterial color="#FEE2E2" roughness={0.9} />
            </mesh>
            <mesh rotation={[-Math.PI/2, 0, 0]} position={[0, -0.9, -0.2]}>
                <torusGeometry args={[1.8, 0.1, 12, 24, Math.PI]} />
                <meshStandardMaterial color="#FEE2E2" roughness={0.9} />
            </mesh>

            {(viewMode === 'both' || viewMode === 'upper') && upperTeeth.map(id => (
              <Tooth key={id} id={id} status={toothData[id]?.status} isSelected={selectedToothId === id} onClick={onToothSelect} showNumbers={showNumbers} />
            ))}
            {(viewMode === 'both' || viewMode === 'lower') && lowerTeeth.map(id => (
              <Tooth key={id} id={id} status={toothData[id]?.status} isSelected={selectedToothId === id} onClick={onToothSelect} showNumbers={showNumbers} />
            ))}
          </group>
        </Center>

        <ContactShadows position={[0, -2.8, 0]} opacity={0.3} scale={20} blur={2} far={10} />
        <OrbitControls makeDefault minDistance={4} maxDistance={12} />
        <Environment preset="city" />
      </Canvas>
      
      {/* FDI Quadrant Markers */}
      <div style={{ position: 'absolute', top: 20, right: 20, pointerEvents: 'none' }}>
         <div style={{ display: 'grid', gridTemplateColumns: '30px 30px', gap: '4px', textAlign: 'center', fontSize: '10px', color: '#94A3B8', fontWeight: 700 }}>
            <div style={{ borderBottom: '1px solid #E5E7EB', borderRight: '1px solid #E5E7EB' }}>1</div>
            <div style={{ borderBottom: '1px solid #E5E7EB' }}>2</div>
            <div style={{ borderRight: '1px solid #E5E7EB' }}>4</div>
            <div>3</div>
         </div>
      </div>
    </div>
  );
}
