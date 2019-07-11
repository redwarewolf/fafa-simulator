using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using System.Linq;

public class Club : MonoBehaviour
{
  public string name { get; set; }
  public List<FootballPlayer> footballPlayers { get; set; }

  public Club(string _name, List<FootballPlayer> _footballPlayers){
    name = _name;
    footballPlayers = _footballPlayers;
  }


  public int power(){
    return footballPlayers.Select( x => x.ability).Sum();
  }
}
