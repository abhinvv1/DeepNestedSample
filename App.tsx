import React, { useState } from 'react';
import { View, Text, StyleSheet, ScrollView, SafeAreaView, Button } from 'react-native';

const App = () => {
  const [complexity, setComplexity] = useState(5);
  
  const generateComplexStructure = (depth = complexity, width = complexity) => {  
    const createNestedObject = (currentDepth, path = '') => {
      if (currentDepth <= 0) return null;
      
      const obj = {};
      
      for (let i = 0; i < width; i++) {
        const newPath = path ? `${path}-${i}` : `${i}`;
        obj[`prop${i}`] = {
          value: newPath,
          children: [],
          metadata: {
            index: i,
            path: newPath,
            level: complexity - currentDepth + 1,
            nestedInfo: {
              details: {
                moreNesting: {
                  evenMore: {
                    deepValue: newPath,
                  }
                }
              }
            }
          }
        };
        
        const childObj = createNestedObject(currentDepth - 1, newPath);
        if (childObj) {
          obj[`prop${i}`].children.push(childObj);
        }
      }
      
      return obj;
    };
    
    return createNestedObject(depth);
  };
  
  const renderComplexData = (data, level = 1) => {
    if (!data) return null;
    
    const components = [];
    
    Object.keys(data).forEach(key => {
      const item = data[key];
      if (typeof item === 'object' && item !== null) {
        const path = item.metadata?.path || 'unknown';
        const currentLevel = item.metadata?.level || level;
        
        components.push(
          <View 
            key={`level-${currentLevel}-${path}`}
            testID={`testID.${currentLevel}.${path}`}
            accessibilityLabel={`accessibilityLabel.${currentLevel}.${path}`}
            style={[
              styles.box,
              {
                backgroundColor: currentLevel % 2 === 0 ? '#e0f7fa' : '#fff9c4',
                marginLeft: currentLevel * 5,
              }
            ]}
          >
            <Text style={styles.text}>{`Level ${currentLevel}: ${path}`}</Text>

            {item.children && item.children.map((child, index) => (
              <View key={`child-${index}`}>
                {renderComplexData(child, currentLevel + 1)}
              </View>
            ))}

            {item.metadata && item.metadata.nestedInfo && (
              <View 
                testID={`nested.${currentLevel}.${path}`}
                style={styles.nestedBox}
              >
                <Text style={styles.nestedText}>Nested data</Text>
              </View>
            )}
          </View>
        );
      }
    });
    
    return components;
  };

  const complexData = generateComplexStructure();

  return (
    <SafeAreaView style={styles.container}>
      <Text style={styles.header}>Complex DOM Structure</Text>
      
      <View style={styles.controls}>
        <Text>Complexity: {complexity}</Text>
        <View style={styles.buttonRow}>
          <Button 
            title="-1" 
            onPress={() => setComplexity(Math.max(3, complexity - 1))}
            testID="decreaseComplexity"
          />
          <Button 
            title="+1" 
            onPress={() => setComplexity(complexity + 1)}
            testID="increaseComplexity"
          />
        </View>
      </View>

      <ScrollView style={styles.scrollView}>
        {renderComplexData(complexData)}
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  header: {
    fontSize: 22,
    fontWeight: 'bold',
    textAlign: 'center',
    marginTop: 20,
    marginBottom: 10,
  },
  controls: {
    alignItems: 'center',
    marginVertical: 10,
  },
  buttonRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    width: 150,
    marginTop: 5,
  },
  description: {
    fontSize: 14,
    textAlign: 'center',
    marginHorizontal: 20,
    marginBottom: 20,
    color: '#555',
  },
  scrollView: {
    flex: 1,
  },
  box: {
    padding: 8,
    borderWidth: 1,
    borderColor: '#ddd',
    marginVertical: 2,
    marginRight: 5,
  },
  text: {
    fontSize: 12,
  },
  nestedBox: {
    padding: 4,
    backgroundColor: '#f5f5f5',
    borderWidth: 1,
    borderColor: '#eee',
    marginTop: 4,
  },
  nestedText: {
    fontSize: 10,
    color: '#777',
  },
});

export default App;
// import {View, Text, Pressable, ScrollView} from 'react-native';


// function App() {
//   const renderTestComponent = (id: number = 1) => {
//     if (id > 250) {
//       return null;
//     }

//     return (
//       <View
//         key={id}
//         testID={`testID.${id}`}
//         accessibilityLabel={`accessibilityLabel.${id}`}
//         style={{
//           backgroundColor: id % 2 === 0 ? 'lightblue' : 'orange',
//           padding: 2,
//         }}>
//         <Pressable>
//           <Text style={{textAlign: 'center'}}>{id.toString()}</Text>
//         </Pressable>
//         {renderTestComponent(id + 1)}
//       </View>
//     );
//   };

//   return (
//     <ScrollView>
//       {renderTestComponent()}
//     </ScrollView>
//   );
// }

// export default App;
