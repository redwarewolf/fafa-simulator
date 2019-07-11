using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using TMPro;

public class Player : MonoBehaviour
{
  public TextMeshProUGUI cash;

  private Club club;

  void Start(){
    cash = GameObject.FindWithTag("Cash").GetComponent<TextMeshProUGUI>();

    cash.text = 5000.ToString();
  }

  public void buy(int cost){
    if (canAfford(cost)){
      cash.text = (toInt(cash.text) - cost).ToString();
      updateUI();
    }
  }

  public bool canAfford(int cost){
    return cost <= toInt(cash.text);
  }

  public void updateUI(){

  }

  private int toInt(string str){
    return int.Parse(str);
  }
}
