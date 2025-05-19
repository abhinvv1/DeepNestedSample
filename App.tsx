import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, SafeAreaView, Button } from 'react-native';

const MAX_WIDTH_PER_NODE = 1;
const EXTRA_WRAPPERS_PER_RENDER_LEVEL = 2;

const App = () => {
  const [logicalComplexity, setLogicalComplexity] = useState(50);
  const [pressCount, setPressCount] = useState(0);

  const handleDeepButtonPress = (path: string) => {
    setPressCount(prev => prev + 1);
    console.log(`Deep button pressed: ${path}, Total Presses: ${pressCount + 1}`);
  };

  // Generates a "skinny" and deep data structure
  const generateComplexStructure = (currentLogicalComplexity: number) => {
    const createNestedObject = (currentDataDepth: number, parentPath: string = ''): object | null => {
      if (currentDataDepth <= 0) return null;

      const obj: { [key: string]: any } = {};
      const currentGeneratedDataLevel = currentLogicalComplexity - currentDataDepth + 1;
      const childIndex = 0;
      const newPath = parentPath ? `${parentPath}-${childIndex}` : `${childIndex}`;
      const uniqueIDSuffix = `${currentGeneratedDataLevel}-${newPath}`;
      const childKey = `prop${childIndex}`;

      if (currentGeneratedDataLevel === currentLogicalComplexity) {
        obj[childKey] = {
          type: 'deepTextNode',
          value: `Deepest Text: L${currentGeneratedDataLevel}, P:${newPath}`,
          path: newPath,
          level: currentGeneratedDataLevel,
          testID: `deep-text-${uniqueIDSuffix}`,
          children: []
        };
      } else if (currentGeneratedDataLevel === currentLogicalComplexity - 1 && currentLogicalComplexity > 1) {
        obj[childKey] = {
          type: 'deepButtonNode',
          title: `Press Deep L${currentGeneratedDataLevel}, P:${newPath}`,
          path: newPath,
          level: currentGeneratedDataLevel,
          testID: `deep-button-${uniqueIDSuffix}`,
          children: []
        };
        if (currentDataDepth - 1 > 0) {
            const deeperChildNodeMap = createNestedObject(currentDataDepth - 1, newPath);
            if (deeperChildNodeMap) {
              obj[childKey].children.push(deeperChildNodeMap);
            }
        }
      } else {
        obj[childKey] = {
          type: 'genericViewNode',
          value: `Generic L${currentGeneratedDataLevel} P:${newPath}`,
          children: [],
          level: currentGeneratedDataLevel,
          testID: `generic-view-${uniqueIDSuffix}`,
          metadata: { index: childIndex, path: newPath, level: currentGeneratedDataLevel, nestedInfo: { details: { moreNesting: { evenMore: { deepValue: `metadata-${newPath}`}}}} },
        };
        const deeperChildNodeMap = createNestedObject(currentDataDepth - 1, newPath);
        if (deeperChildNodeMap) {
          obj[childKey].children.push(deeperChildNodeMap);
        }
      }
      return obj;
    };
    return createNestedObject(currentLogicalComplexity, '');
  };

  const renderComplexData = (data: any, currentContentRenderLevel = 1): JSX.Element[] | null => {
    if (!data || typeof data !== 'object') return null;

    const components: JSX.Element[] = [];

    Object.keys(data).forEach(key => {
      const item = data[key];
      if (!item || typeof item !== 'object') return;

      const itemPath = item.path || 'unknown_path';
      const logicalDataLevel = item.level || 1;
      const baseTestID = item.testID || `generic-${logicalDataLevel}-${itemPath}`;

      let contentChildren: JSX.Element[] | null = null;
      if (item.children && item.children.length > 0) {
        contentChildren = item.children.flatMap((childData: any) =>
          renderComplexData(childData, currentContentRenderLevel + EXTRA_WRAPPERS_PER_RENDER_LEVEL + 1) || []
        );
      }

      let contentComponentCore: JSX.Element | null = null;
      const contentWrapperStyle = [
        styles.box,
        {
          paddingLeft: (currentContentRenderLevel % 5) + 2,
          backgroundColor: `rgba(200, 200, 255, ${0.1 + (currentContentRenderLevel % 7) * 0.025})`,
          borderColor: `rgba(100, 100, 100, ${0.2 + (currentContentRenderLevel % 5) * 0.05})`,
          borderWidth: 1,
          opacity: 0.95 + (currentContentRenderLevel % 5) * 0.01,
        },
      ];
      const contentWrapperAccessibilityLabel = `Content Wrapper for ${item.type} ${itemPath} at render level ${currentContentRenderLevel}`;


      if (item.type === 'deepTextNode') {
        contentComponentCore = (
          <View
            collapsable={false}
            key={`${baseTestID}-content-core`}
            testID={`wrapper-content-${baseTestID}`}
            accessibilityLabel={contentWrapperAccessibilityLabel}
            style={contentWrapperStyle}
          >
            <Text testID={baseTestID} style={styles.deepTextStyle}>
              {item.value}
            </Text>
            {contentChildren}
          </View>
        );
      } else if (item.type === 'deepButtonNode') {
        contentComponentCore = (
          <View
            collapsable={false}
            key={`${baseTestID}-content-core`}
            testID={`wrapper-content-${baseTestID}`}
            accessibilityLabel={contentWrapperAccessibilityLabel}
            style={contentWrapperStyle}
          >
            <Button
              title={item.title}
              onPress={() => handleDeepButtonPress(itemPath)}
              testID={baseTestID}
              color="#FF1493"
            />
            {contentChildren}
          </View>
        );
      } else if (item.type === 'genericViewNode' && item.value !== undefined) {
        contentComponentCore = (
          <View
            collapsable={false}
            key={`${baseTestID}-content-core`}
            testID={`wrapper-content-${baseTestID}`}
            accessibilityLabel={contentWrapperAccessibilityLabel}
            style={contentWrapperStyle}
          >
            <Text style={styles.text}>{item.value}</Text>
            <Text style={styles.textMuted}>{`(LData:${logicalDataLevel}, ContentRenderL:${currentContentRenderLevel}, P:${itemPath})`}</Text>
            {item.metadata && item.metadata.nestedInfo && (
              <View
                collapsable={false}
                testID={`nested-metadata.${item.metadata.level}.${item.metadata.path}`}
                style={styles.nestedBox}
                accessibilityLabel={`Original Metadata for ${item.metadata.path}`}
              >
                <Text style={styles.nestedText}>Meta L:{item.metadata.level} P:{item.metadata.path}</Text>
              </View>
            )}
            {contentChildren}
          </View>
        );
      }


      if (contentComponentCore) {
        let wrappedComponent = contentComponentCore;
        for (let i = 0; i < EXTRA_WRAPPERS_PER_RENDER_LEVEL; i++) {
          const actualWrapperRenderLevel = currentContentRenderLevel + i;
          wrappedComponent = (
            <View
              collapsable={false}
              key={`${baseTestID}-extra-wrapper-${i}-renderlevel-${actualWrapperRenderLevel}`}
              testID={`extra-wrapper-${logicalDataLevel}-${itemPath}-${i}-renderlevel-${actualWrapperRenderLevel}`}
              accessibilityLabel={`Extra Wrapper ${i} for ${itemPath} at actual render level ${actualWrapperRenderLevel}`}
              accessibilityHint={`Hint for Extra Wrapper ${i}, render level ${actualWrapperRenderLevel}`}
              style={{
                // padding: 0.75,
                // margin: 0.75,
                borderWidth: 1,
                borderColor: `rgba(0,0,${100 + (actualWrapperRenderLevel % 155)}, ${0.2 + (actualWrapperRenderLevel % 8) * 0.1})`, // Thanks to ChatGPT for this color logic
              }}
            >
              {wrappedComponent}
            </View>
          );
        }
        components.push(wrappedComponent);
      }
    });
    return components;
  };

  const complexData = generateComplexStructure(logicalComplexity);
  const effectiveMaxRenderDepth = logicalComplexity * (1 + EXTRA_WRAPPERS_PER_RENDER_LEVEL);

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.headerContainer}>
        <Text style={styles.header}>Deep Nested UI</Text>
        <Text testID="press-counter" style={styles.counterText}>
          Presses: {pressCount}
        </Text>
      </View>

      <Text style={styles.infoText}>
        {`Each logical level's content is wrapped by ${EXTRA_WRAPPERS_PER_RENDER_LEVEL} unique, non-collapsible Views.`}
      </Text>

      <ScrollView style={styles.scrollView} testID="mainScrollView">
        {complexData ? renderComplexData(complexData) : <Text>No data to render.</Text>}
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#ECEFF1',
  },
  headerContainer: {
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: '#B0BEC5',
    alignItems: 'center',
    backgroundColor: '#CFD8DC',
  },
  header: {
    fontSize: 17,
    fontWeight: 'bold',
    textAlign: 'center',
    color: '#263238',
  },
  counterText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#0D47A1',
    textAlign: 'center',
    marginTop: 5,
  },
  controls: {
    alignItems: 'center',
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: '#B0BEC5',
    backgroundColor: '#ECEFF1',
  },
  complexityText: {
    fontSize: 13,
    marginBottom: 3,
    textAlign: 'center',
    color: '#37474F',
  },
  buttonRow: {
    flexDirection: 'row',
    justifyContent: 'space-evenly',
    width: '90%',
    marginTop: 7,
  },
  infoText: {
    fontSize: 10,
    textAlign: 'center',
    marginHorizontal: 10,
    marginVertical: 8,
    color: '#455A64',
  },
  scrollView: {
    flex: 1,
  },
  box: {
    padding: 3,
    marginVertical: 0,
    borderRadius: 2,
  },
  text: {
    fontSize: 11,
    fontWeight: 'normal',
    color: '#1A237E',
  },
  textMuted: {
    fontSize: 8,
    color: '#546E7A',
  },
  deepTextStyle: {
    fontSize: 12,
    fontWeight: 'bold',
    color: '#1B5E20',
  },
  nestedBox: {
    padding: 2,
    backgroundColor: 'rgba(255, 243, 224, 0.6)',
    borderWidth: 1,
    borderColor: 'rgba(255, 204, 128, 0.6)',
    marginTop: 2,
    borderRadius: 1,
  },
  nestedText: {
    fontSize: 9,
    color: '#E65100',
    fontWeight: '500',
  }
});

export default App;
