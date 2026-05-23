import { useState } from 'react';
import { Button, ScrollView, Text as RNText, StyleSheet, View } from 'react-native';
import { Image, Video, Text } from 'expo-content-safety';

export default function App() {
  const [output, setOutput] = useState<string>('Tap a button to call the stub.');

  async function runImage() {
    try {
      const result = await Image.detect('file:///placeholder.jpg');
      setOutput(JSON.stringify(result, null, 2));
    } catch (e: any) {
      setOutput(`ERROR: ${e.code} ${e.message}`);
    }
  }

  async function runVideo() {
    try {
      const result = await Video.detect('file:///placeholder.mp4');
      setOutput(JSON.stringify(result, null, 2));
    } catch (e: any) {
      setOutput(`ERROR: ${e.code} ${e.message}`);
    }
  }

  async function runText() {
    try {
      const result = await Text.detect('hello world');
      setOutput(JSON.stringify(result, null, 2));
    } catch (e: any) {
      setOutput(`ERROR: ${e.code} ${e.message}`);
    }
  }

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <RNText style={styles.title}>expo-content-safety smoke test</RNText>
      <Button title="detect image" onPress={runImage} />
      <View style={styles.spacer} />
      <Button title="detect video" onPress={runVideo} />
      <View style={styles.spacer} />
      <Button title="detect text" onPress={runText} />
      <View style={styles.spacer} />
      <RNText style={styles.output}>{output}</RNText>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { padding: 24, paddingTop: 80 },
  title: { fontSize: 18, fontWeight: '600', marginBottom: 16 },
  spacer: { height: 12 },
  output: { marginTop: 24, fontFamily: 'Courier', fontSize: 12 },
});
