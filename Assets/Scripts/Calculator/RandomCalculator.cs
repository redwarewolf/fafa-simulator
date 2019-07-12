using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class RandomCalculator : MonoBehaviour
{

  static public bool evaluateChances(float chance){
    return chance <= Random.Range(0,100);
  }
}
