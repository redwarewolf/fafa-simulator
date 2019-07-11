using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using System.Linq;

public class Club : MonoBehaviour
{
  private string name;
  private List<FootballPlayer> footballPlayers;

  public Club(string _name, List<FootballPlayer> _footballPlayers){
    name = _name;
    footballPlayers = _footballPlayers;
  }


  public int power(){
    return footballPlayers.Select( x => x.power()).Sum();
  }
}
