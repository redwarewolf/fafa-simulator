using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class RandomCalculator : MonoBehaviour
{

  public bool evaluateEvent(float chance){
    return chance <= Random.Range(0,100);
  }
}
