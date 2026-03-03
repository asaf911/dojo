import React from 'react';
import { TouchableOpacity, Image, StyleSheet } from 'react-native';

interface ButtonViewProps {
  onPress?: () => void;
  style?: object;
}

const ButtonView: React.FC<ButtonViewProps> = ({ onPress, style }) => {
  return (
    <TouchableOpacity 
      onPress={onPress} 
      style={[styles.button, style]}
      activeOpacity={0.7}
    >
      <Image 
        source={require('../assets/buttonSettings.png')}
        style={styles.image}
        resizeMode="contain"
      />
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  button: {
    padding: 10,
    justifyContent: 'center',
    alignItems: 'center',
  },
  image: {
    width: 24,
    height: 24,
  },
});

export default ButtonView; 