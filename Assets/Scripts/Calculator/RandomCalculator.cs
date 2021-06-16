using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class RandomCalculator : MonoBehaviour
{

  static public bool evaluateChances(float chance){
    // Change this to float in the future for more precision.
    int randomNumber = Random.Range(0, 101);

    return chance <= randomNumber;
  }
}
