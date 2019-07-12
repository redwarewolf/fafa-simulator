using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Player : MonoBehaviour
{

  static public int cash;
  static public string name { get; set; }
  static public Club club { get; set; }

  public UIupdater uiUpdater;

  public Player(){

    if (name == null){
      //If any of the variables is null, it means the player's data hasnt been loaded.
      // This should be replaced with loading from a file.

      cash = 5000;
      name = "Pedro";
      club = new ClubFactory().newClub("Pedro's Club", 3);
    }
  }

  void Start(){
    setUIUpdater();
    updateUI();
  }

  public void buy(int cost){
    if (canAfford(cost)){
      cash -= cost;
      updateUI();
    }
  }

  public bool canAfford(int cost){
    return cost <= cash;
  }

  public void updateUI(){
    if (uiUpdater == null){
      setUIUpdater();
    }
    uiUpdater.updateUI();
  }

  public int getCash(){
    return cash;
  }

  public void setCash(int _cash){
    cash = _cash;
  }

  public void addCash(int _cash){
    cash += _cash;
    updateUI();
  }

  public void setUIUpdater(){
    uiUpdater = GameObject.FindWithTag("GameMaster").GetComponent<UIupdater>();
  }

  private int toInt(string str){
    return int.Parse(str);
  }
}
