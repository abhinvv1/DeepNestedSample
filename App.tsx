import {View, Text, Pressable, ScrollView} from 'react-native';


function App() {
  const renderTestComponent = (id: number = 1) => {
    if (id > 60) {
      return null;
    }

    return (
      <View
        key={id}
        testID={`testID.${id}`}
        accessibilityLabel={`accessibilityLabel.${id}`}
        style={{
          backgroundColor: id % 2 === 0 ? 'lightblue' : 'orange',
          padding: 2,
        }}>
        <Pressable>
          <Text style={{textAlign: 'center'}}>{id.toString()}</Text>
        </Pressable>
        {renderTestComponent(id + 1)}
      </View>
    );
  };

  return (
    <ScrollView>
      {renderTestComponent()}
    </ScrollView>
  );
}

export default App;
